"""核对31005/J13接线合同、文档、CST及可选实现报告；不替代实物通断/电压检查。"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "verification/data/board_31005_j13.json"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_cst(path=None):
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    path = Path(path) if path else ROOT / contract["cst"]
    body = path.read_text(encoding="utf-8-sig")
    locations = re.findall(r'IO_LOC\s+"([^"]+)"\s+([A-Z]+\d+);', body)
    ports = dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+([^;]+);', body))
    expected = {**contract["unchanged_locations"], **{s["port"]: s["ball"] for s in contract["signals"]}}
    if len(locations) != 25 or dict(locations) != expected or len({p for _, p in locations}) != 25:
        raise ValueError("J13 CST pin mismatch, duplicate pin or unchanged port moved")
    fixed_attributes = {"sys_clk": "IO_TYPE=LVCMOS33", "sys_rst_n": "IO_TYPE=LVCMOS15 PULL_MODE=UP",
                        "Key_in[0]": "IO_TYPE=LVCMOS15 PULL_MODE=UP", "Key_in[1]": "IO_TYPE=LVCMOS15 PULL_MODE=UP",
                        "uart_rx": "IO_TYPE=LVCMOS33 PULL_MODE=UP",
                        **{name: "IO_TYPE=LVCMOS33 DRIVE=8" for name in ("HP_BCK", "HP_WS", "HP_DIN", "PA_EN", "uart_tx")}}
    if len(ports) != 25 or any(" ".join(ports.get(k, "").split()) != v for k, v in fixed_attributes.items()):
        raise ValueError("Unchanged I/O electrical attributes changed")
    if len(contract["signals"]) != 15 or len({s["j13_pin"] for s in contract["signals"]}) != 15:
        raise ValueError("J13 signal inventory mismatch")
    # 外部模块K编号属于装配合同，不能退回半音顺序后还称八白键连续。
    by_port={s['port']:s for s in contract['signals']}
    for pin,bit in zip(range(1,9),(0,2,4,5,7,9,11,12)):
        if by_port[f'piano_key_n[{bit}]']['j13_pin']!=pin:
            raise ValueError('Eight white keys are not consecutive at J13-1..8')
    for pin,bit in zip((9,10,13,14,15),(1,3,6,8,10)):
        if by_port[f'piano_key_n[{bit}]']['j13_pin']!=pin:
            raise ValueError('Five black keys mapping mismatch')
    for signal in contract["signals"]:
        if signal["j13_pin"] in (11, 12) or not 1 <= signal["j13_pin"] <= 40:
            raise ValueError("J13 signal assigned to power/ground or invalid pin")
        if signal["bank"] not in (1, 2):
            raise ValueError("J13 expected 3.3V Bank1/2")
        attributes = " ".join(ports.get(signal["port"], "").split())
        expected_attributes = "IO_TYPE=LVCMOS33 " + ("" if signal["port"] == "knob_scl" else "PULL_MODE=UP ") + "BANK_VCCIO=3.3"
        if attributes != expected_attributes:
            raise ValueError("J13 I/O voltage/pull mismatch: " + signal["port"])
    return contract, {"board": contract["board"], "ports": 25, "migrated_signals": 15,
                      "cst_sha256": digest(path), "contract_sha256": digest(CONTRACT_PATH),
                      "checker_sha256": digest(Path(__file__)),
                      "previous_cst_sha256": contract["previous_cst_sha256"],
                      "hardware_measured": False}


def validate_report(path, contract):
    rows = {}
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        cells = [x.strip() for x in line.split("|")]
        if len(cells) > 5 and re.fullmatch(r"\w+(?:\[\d+\])?", cells[0]) and re.fullmatch(r"[A-Z]+\d+/\d+", cells[2]):
            rows[cells[0]] = cells
    for signal in contract["signals"]:
        row = rows.get(signal["port"], [])
        if not row or row[2] != f"{signal['ball']}/{signal['bank']}" or row[3] != "Y" or "LVCMOS33" not in row:
            raise ValueError("Implemented J13 pin/bank/voltage mismatch: " + signal["port"])
        # Gowin文本报告使用in/out/io小写，而不是Verilog端口关键字。
        direction = "in" if signal["port"].startswith("piano_key_n[") else "out" if signal["port"] == "knob_scl" else "io"
        if row[4] != direction or len(row) <= 17 or row[17] != "3.3":
            raise ValueError("Implemented J13 direction mismatch: " + signal["port"])
    return digest(Path(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cst", type=Path)
    parser.add_argument("--report", action="append", type=Path, default=[])
    parser.add_argument("--device-json", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--negative-control", action="store_true", help="Reject three generated faults under build/")
    args = parser.parse_args()
    contract, result = validate_cst(args.cst)
    doc = (ROOT / "docs/keyboard-wiring.md").read_text(encoding="utf-8")
    for signal in contract["signals"]:
        if not re.search(rf"\|[^\n]*{re.escape(signal['port'])}[^\n]*\| J13 第{signal['j13_pin']}脚[^\n]*\| {signal['ball']} \| {signal['bank']} \|", doc):
            raise ValueError("Wiring document mismatch: " + signal["port"])
    if args.device_json:
        device = {p["INDEX"]: p for p in json.loads(args.device_json.read_text())["PIN_DATA"]}
        for signal in contract["signals"]:
            pin = device[signal["ball"]]
            if pin["TYPE"] != "I/O" or pin["BANK"] != signal["bank"]:
                raise ValueError("Device package mismatch: " + signal["port"])
        result["device_json_sha256"] = digest(args.device_json)
    result["reports"] = {str(p): validate_report(p, contract) for p in args.report}
    if args.negative_control:
        if not args.report:raise ValueError('Negative report check requires --report')
        faults=ROOT/'build/integration/20261016/pin_negative'
        faults.mkdir(parents=True,exist_ok=True)
        cst=ROOT/contract['cst'];body=cst.read_text(encoding='utf-8-sig')
        cases=[('pin',body.replace('IO_LOC "piano_key_n[0]" E14;','IO_LOC "piano_key_n[0]" E13;',1)),
            ('voltage',body.replace('IO_PORT "knob_scl" IO_TYPE=LVCMOS33','IO_PORT "knob_scl" IO_TYPE=LVCMOS18',1))]
        rejected=[]
        for name,changed in cases:
            if changed==body:raise ValueError('Missing pin mutation target')
            fault=faults/(name+'.cst');fault.write_text(changed,encoding='utf-8')
            try:validate_cst(fault)
            except ValueError as error:rejected.append({'case':name,'rejected':str(error)})
            else:raise ValueError('Pin fault survived: '+name)
        report=args.report[0].read_text(encoding='utf-8-sig')
        changed=re.sub(r'(?m)^(piano_key_n\[0\].*)E14/1',r'\1E13/1',report,count=1)
        if changed==report:raise ValueError('Missing implementation mutation target')
        fault=faults/'report.rpt.txt';fault.write_text(changed,encoding='utf-8')
        try:validate_report(fault,contract)
        except ValueError as error:rejected.append({'case':'report','rejected':str(error)})
        else:raise ValueError('Wrong actual pin report survived')
        result['negative_controls']=rejected
    result["checker_sha256"] = digest(Path(__file__))
    result["status"] = "PASS_PIN_CONTRACT_ONLY"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PASS J13: 13 keys + SDA/SCL; power pins excluded; unchanged 10 locations")


if __name__ == "__main__":
    main()
