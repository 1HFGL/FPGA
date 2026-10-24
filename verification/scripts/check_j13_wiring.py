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
    # 用户2026-10-24确认的实物白键；独立核对球位、Bank、排针及BTB链路。
    by_port={s['port']:s for s in contract['signals']}
    white_keys = ((0,39,'C19',2,16,'SDRAM0_A2','C2399'),
                  (2,37,'D19',2,10,'SDRAM0_A0','C2399'),
                  (4,35,'C20',2,4,'SDRAM0_BA1','C2399'),
                  (5,33,'F19',2,68,'SDRAM0_CS','BTB8900'),
                  (7,31,'E17',1,22,'SDRAM0_CAS','C2399'),
                  (9,29,'F14',1,42,'SDRAM0_DM0','C2399'),
                  (11,27,'D16',1,28,'SDRAM0_WE','C2399'),
                  (12,25,'D15',1,34,'SDRAM0_A5','C2399'))
    for bit,pin,ball,bank,btb,net,connector in white_keys:
        signal=by_port[f'piano_key_n[{bit}]']
        if tuple(signal[k] for k in ('j13_pin','ball','bank','btb_pin','net','core_connector')) != (pin,ball,bank,btb,net,connector):
            raise ValueError('Eight white keys mapping mismatch')
    if by_port['piano_key_n[9]'].get('series_resistor') != 'R68':
        raise ValueError('F14 to J13-29 requires dock R68 route')
    # 2026-10-22用户确认的五黑键；独立检查整条底板→BTB→60K链路。
    black_keys = ((1,40,'C18',2,18,'SDRAM0_A3'), (3,38,'E19',2,12,'SDRAM0_A1'),
                  (6,36,'D20',2,6,'SDRAM0_A10'), (8,34,'F15',1,40,'SDRAM0_BA0'),
                  (10,32,'F16',1,24,'SDRAM0_RAS'))
    for bit,pin,ball,bank,btb,net in black_keys:
        signal=by_port[f'piano_key_n[{bit}]']
        if tuple(signal[k] for k in ('j13_pin','ball','bank','btb_pin','net')) != (pin,ball,bank,btb,net):
            raise ValueError('Five black keys mapping mismatch')
    reserved=contract.get('bluetooth',[])
    ble_routes = [('RXD','ble_tx','C13',6,55,'SDRAM0_D5'),
                  ('TXD','ble_rx','C14',4,61,'SDRAM0_D3'),
                  ('STATE','ble_state','C15',3,59,'SDRAM0_D2')]
    if [tuple(s[k] for k in ('module_pin','port','ball','j13_pin','btb_pin','net')) for s in reserved] != ble_routes or any(s['bank']!=1 or s['core_connector']!='C2399' for s in reserved):
        raise ValueError('Bluetooth mapping mismatch')
    if any(s['ball'] in expected.values() or s['j13_pin'] in {v['j13_pin'] for v in contract['signals']} for s in reserved):
        raise ValueError('Bluetooth conflicts with a key/ADC port')
    validate_ble_cst(ROOT/contract['bluetooth_cst'],contract)
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
                      "bluetooth_ports": 3, "bluetooth_cst_sha256": digest(ROOT/contract['bluetooth_cst']),
                      "cst_sha256": digest(path), "contract_sha256": digest(CONTRACT_PATH),
                      "checker_sha256": digest(Path(__file__)),
                      "previous_cst_sha256": contract["previous_cst_sha256"],
                      "hardware_measured": False}


def validate_ble_cst(path,contract):
    body=Path(path).read_text(encoding='utf-8-sig')
    pins=re.findall(r'IO_LOC\s+"([^"]+)"\s+([A-Z]+\d+);',body)
    expected={s['port']:s['ball'] for s in contract['bluetooth']}
    if len(pins)!=3 or dict(pins)!=expected or len(set(expected.values()))!=3:
        raise ValueError('BLE pin mismatch/duplicate')
    attrs=dict(re.findall(r'IO_PORT\s+"([^"]+)"\s+([^;]+);',body))
    expected_attrs={
        'ble_tx':'IO_TYPE=LVCMOS33 DRIVE=8 BANK_VCCIO=3.3',
        'ble_rx':'IO_TYPE=LVCMOS33 PULL_MODE=UP BANK_VCCIO=3.3',
        'ble_state':'IO_TYPE=LVCMOS33 PULL_MODE=DOWN BANK_VCCIO=3.3'}
    if {k:' '.join(v.split()) for k,v in attrs.items()}!=expected_attrs:
        raise ValueError('BLE I/O voltage/pull/drive mismatch')


def validate_report(path, contract):
    rows = {}
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        cells = [x.strip() for x in line.split("|")]
        if len(cells) > 5 and re.fullmatch(r"\w+(?:\[\d+\])?", cells[0]) and re.fullmatch(r"[A-Z]+\d+/\d+", cells[2]):
            rows[cells[0]] = cells
    for signal in contract["signals"] + contract['bluetooth']:
        row = rows.get(signal["port"], [])
        if not row or row[2] != f"{signal['ball']}/{signal['bank']}" or row[3] != "Y" or "LVCMOS33" not in row:
            raise ValueError("Implemented J13 pin/bank/voltage mismatch: " + signal["port"])
        # Gowin文本报告使用in/out/io小写，而不是Verilog端口关键字。
        direction = "in" if signal["port"].startswith("piano_key_n[") or signal['port'] in ('ble_rx','ble_state') else "out" if signal["port"] in ("knob_scl",'ble_tx') else "io"
        if row[4] != direction or len(row) <= 17 or row[17] != "3.3":
            raise ValueError("Implemented J13 direction mismatch: " + signal["port"])
    return digest(Path(path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cst", type=Path)
    parser.add_argument("--report", action="append", type=Path, default=[])
    parser.add_argument("--device-json", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--negative-control", action="store_true", help="Reject pin, voltage and report faults under build/")
    args = parser.parse_args()
    contract, result = validate_cst(args.cst)
    doc = (ROOT / "docs/keyboard-wiring.md").read_text(encoding="utf-8")
    for signal in contract["signals"]:
        if not re.search(rf"\|[^\n]*{re.escape(signal['port'])}[^\n]*\| J13 第{signal['j13_pin']}脚[^\n]*\| {signal['ball']} \| {signal['bank']} \|", doc):
            raise ValueError("Wiring document mismatch: " + signal["port"])
    for signal in contract['bluetooth']:
        if not re.search(rf"\| {re.escape(signal['module_pin'])} \| {signal['ball']}（J13第{signal['j13_pin']}脚） \|",doc):
            raise ValueError('BLE wiring document mismatch: '+signal['module_pin'])
    if args.device_json:
        device = {p["INDEX"]: p for p in json.loads(args.device_json.read_text())["PIN_DATA"]}
        for signal in contract["signals"] + contract['bluetooth']:
            pin = device[signal["ball"]]
            if pin["TYPE"] != "I/O" or pin["BANK"] != signal["bank"]:
                raise ValueError("Device package mismatch: " + signal.get("port", signal.get("module_pin", "unknown")))
        result["device_json_sha256"] = digest(args.device_json)
    result["reports"] = {str(p): validate_report(p, contract) for p in args.report}
    if args.negative_control:
        if not args.report:raise ValueError('Negative report check requires --report')
        faults=ROOT/'build/pin_migration_20261024/negative'
        faults.mkdir(parents=True,exist_ok=True)
        cst=ROOT/contract['cst'];body=cst.read_text(encoding='utf-8-sig')
        cases=[('pin',body.replace('IO_LOC "piano_key_n[0]" C19;','IO_LOC "piano_key_n[0]" D19;',1)),
            ('old_white_pin',body.replace('IO_LOC "piano_key_n[0]" C19;','IO_LOC "piano_key_n[0]" E14;',1)),
            ('old_black_pin',body.replace('IO_LOC "piano_key_n[1]" C18;','IO_LOC "piano_key_n[1]" B16;',1)),
            ('voltage',body.replace('IO_PORT "knob_scl" IO_TYPE=LVCMOS33','IO_PORT "knob_scl" IO_TYPE=LVCMOS18',1))]
        rejected=[]
        for name,changed in cases:
            if changed==body:raise ValueError('Missing pin mutation target')
            fault=faults/(name+'.cst');fault.write_text(changed,encoding='utf-8')
            try:validate_cst(fault)
            except ValueError as error:rejected.append({'case':name,'rejected':str(error)})
            else:raise ValueError('Pin fault survived: '+name)
        report=args.report[0].read_text(encoding='utf-8-sig')
        changed=re.sub(r'(?m)^(piano_key_n\[0\].*)C19/2',r'\1D19/2',report,count=1)
        if changed==report:raise ValueError('Missing implementation mutation target')
        fault=faults/'report.rpt.txt';fault.write_text(changed,encoding='utf-8')
        try:validate_report(fault,contract)
        except ValueError as error:rejected.append({'case':'report','rejected':str(error)})
        else:raise ValueError('Wrong actual pin report survived')
        ble=ROOT/contract['bluetooth_cst'];ble_body=ble.read_text(encoding='utf-8-sig')
        for name,changed in [('ble_pin',ble_body.replace('"ble_tx" C13','"ble_tx" C19')),
                             ('ble_voltage',ble_body.replace('BANK_VCCIO=3.3','BANK_VCCIO=1.8',1))]:
            if changed==ble_body:raise ValueError('Missing BLE mutation target')
            fault=faults/(name+'.cst');fault.write_text(changed,encoding='utf-8')
            try:validate_ble_cst(fault,contract)
            except ValueError as error:rejected.append({'case':name,'rejected':str(error)})
            else:raise ValueError('BLE fault survived: '+name)
        result['negative_controls']=rejected
    result["checker_sha256"] = digest(Path(__file__))
    result["status"] = "PASS_PIN_CONTRACT_ONLY"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PASS J13: 13 keys + SDA/SCL + 3 BLE; power pins excluded; unchanged 10 locations")


if __name__ == "__main__":
    main()
