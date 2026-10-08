"""Async serial transport, explicit device handshake, and a silent simulator."""
import queue
from collections import deque
from PySide6.QtCore import QObject, QThread, QTimer, Signal, Slot

from studio_model import Tone, apply_command, decode_apply


class LineDecoder:
    """Accept fragmented ASCII lines; discard overlong lines until a newline."""
    def __init__(self):
        self.buffer = bytearray()
        self.dropping = False

    def feed(self, data):
        lines = []
        for byte in data:
            if byte == 10:
                if not self.dropping and self.buffer:
                    try:
                        line = self.buffer.decode("ascii").rstrip("\r")
                        if all(32 <= ord(c) < 127 for c in line):
                            lines.append(line)
                    except UnicodeDecodeError:
                        pass
                self.buffer.clear()
                self.dropping = False
            elif not self.dropping:
                self.buffer.append(byte)
                if len(self.buffer) > 512:
                    self.buffer.clear()
                    self.dropping = True
        return lines


class SerialTransport(QThread):
    opened = Signal()
    line = Signal(str)
    error = Signal(str)
    closed = Signal()
    traffic = Signal(int, int)

    def __init__(self, port, baud, parent=None):
        super().__init__(parent)
        self.port, self.baud = port, baud
        self.outbound = queue.Queue(maxsize=64)

    def send(self, text):
        try:
            self.outbound.put_nowait((text + "\n").encode("ascii"))
        except queue.Full:
            raise RuntimeError("发送队列已满，请停止连续操作后重连") from None

    def run(self):
        import serial
        try:
            with serial.Serial(self.port, self.baud, timeout=0.03,
                               write_timeout=0.3, rtscts=False, dsrdtr=False) as port:
                self.opened.emit()
                decoder = LineDecoder()
                while True:
                    try:
                        payload = self.outbound.get_nowait()
                    except queue.Empty:
                        payload = None
                    if self.isInterruptionRequested() and payload is None:
                        break
                    if payload is not None:
                        written = port.write(payload)
                        if written != len(payload):
                            raise RuntimeError("串口未写完一条命令")
                        self.traffic.emit(written, 0)
                    data = port.read(max(1, min(port.in_waiting, 256)))
                    if data:
                        self.traffic.emit(0, len(data))
                        for line in decoder.feed(data):
                            self.line.emit(line)
        except Exception as exc:
            self.error.emit(str(exc))
        finally:
            self.closed.emit()

    def close(self):
        self.requestInterruption()
        # Read/write timeouts bound shutdown; never destroy a running QThread.
        if not self.wait(1500):
            raise RuntimeError("串口线程仍在退出，请稍后再关闭窗口")


class MockTransport(QObject):
    opened = Signal()
    line = Signal(str)
    error = Signal(str)
    closed = Signal()
    traffic = Signal(int, int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.running = False
        self.tone = Tone()
        self.notes = []
        self.steals = 0
        self.peak_voices = 0
        self.replies = deque()
        self.reply_timer = QTimer(self)
        self.reply_timer.setSingleShot(True)
        self.reply_timer.timeout.connect(self._deliver)

    def start(self):
        self.running = True
        QTimer.singleShot(20, lambda: self.opened.emit() if self.running else None)

    def reply(self, text):
        # A UART stream preserves order. Independent equal-delay QTimers don't.
        self.replies.append(text)
        if not self.reply_timer.isActive():
            self.reply_timer.start(35)

    def _deliver(self):
        if self.running and self.replies:
            text = self.replies.popleft()
            self.traffic.emit(0, len(text) + 1)
            self.line.emit(text)
        if self.running and self.replies and not self.reply_timer.isActive():
            self.reply_timer.start(35)

    def send(self, text):
        if not self.running:
            raise RuntimeError("模拟设备已断开")
        self.traffic.emit(len(text) + 1, 0)
        fields = text.split()
        if text == "HELLO":
            self.reply("SYNTH/1 CAPS=CONFIG,NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=simulator")
        elif text.startswith("APPLY "):
            try:
                sequence, tone = decode_apply(text)
                self.tone = tone
                self.reply(f"APPLIED {sequence}")
            except (ValueError, IndexError) as exc:
                self.reply(f"ERROR {fields[1] if len(fields) > 1 else 0} {exc}".encode(
                    "ascii", "replace").decode("ascii"))
        elif text == "STATUS?":
            self.status_reply()
        elif len(fields) == 4 and fields[0] == "NOTE_ON":
            note = int(fields[1])
            if note in self.notes:
                self.notes.remove(note)
            if len(self.notes) == 4:
                self.notes.pop(0)
                self.steals += 1
            self.notes.append(note)
            self.peak_voices = max(self.peak_voices, len(self.notes))
            self.status_reply()
        elif len(fields) == 3 and fields[0] == "NOTE_OFF":
            note = int(fields[1])
            if note in self.notes:
                self.notes.remove(note)
            self.status_reply()
        elif text == "PANIC":
            self.notes.clear()
            self.status_reply()
        else:
            self.reply("ERROR 0 UNSUPPORTED")

    def status_reply(self):
        self.reply(f"STATUS VOICE_COUNT={len(self.notes)} MAX_VOICE_COUNT={self.peak_voices} "
                   f"STEAL_COUNT={self.steals} SAMPLE_RATE=48000")

    def close(self):
        self.running = False
        self.reply_timer.stop()
        self.replies.clear()
        self.notes.clear()
        self.closed.emit()


class StudioSession(QObject):
    changed = Signal()
    log = Signal(str, str)
    status_changed = Signal(dict)

    def __init__(self, parent=None):
        super().__init__(parent)
        self.transport = None
        self.ready = False
        self.simulated = False
        self.label = "未连接"
        self.capabilities = set()
        self.device = {}
        self.status = {}
        self.applied = None
        self.pending = None
        self.sequence = 0
        self.tx_bytes = self.rx_bytes = 0
        self.handshake_timer = QTimer(self)
        self.handshake_timer.setSingleShot(True)
        self.handshake_timer.timeout.connect(self._handshake_timeout)
        self.apply_timer = QTimer(self)
        self.apply_timer.setSingleShot(True)
        self.apply_timer.timeout.connect(self._apply_timeout)
        self.poll = QTimer(self)
        self.poll.setInterval(1000)
        self.poll.timeout.connect(self.query_status)

    def connect_device(self, port, baud=115200, transport=None):
        if self.transport is not None:
            raise RuntimeError("请先断开当前设备")
        self.simulated = port == "SIM"
        self.label = "正在连接…"
        self.tx_bytes = self.rx_bytes = 0
        self.transport = transport or (MockTransport(self) if self.simulated else
                                      SerialTransport(port, baud, self))
        self.transport.opened.connect(self._opened)
        self.transport.line.connect(self._line)
        self.transport.error.connect(self._error)
        self.transport.closed.connect(self._closed)
        self.transport.traffic.connect(self._traffic)
        self.changed.emit()
        self.transport.start()

    @Slot()
    def _opened(self):
        if self.sender() is not self.transport:
            return
        self.label = "串口已打开，等待设备确认…"
        self.send("HELLO")
        self.handshake_timer.start(1800)
        self.changed.emit()

    def send(self, line):
        if self.transport is None:
            raise RuntimeError("请先连接设备")
        self.transport.send(line)
        self.log.emit("发送", line)

    def apply(self, tone):
        if not self.ready or "CONFIG" not in self.capabilities:
            raise RuntimeError("设备未确认支持音色配置")
        if self.pending is not None:
            raise RuntimeError("上一份配置尚未确认，请稍候")
        tone.validate()
        self.sequence += 1
        self.pending = (self.sequence, tone.copy())
        try:
            self.send(apply_command(self.sequence, tone))
        except Exception:
            self.pending = None
            raise
        self.apply_timer.start(1800)
        self.changed.emit()

    @Slot(str)
    def _line(self, line):
        if self.sender() is not self.transport:
            return
        self.log.emit("收到", line)
        if line.startswith("SYNTH/1 ") and self.handshake_timer.isActive():
            fields = dict(item.split("=", 1) for item in line.split()[1:] if "=" in item)
            try:
                maximum = int(fields["MAX_VOICES"])
                rate = int(fields["SAMPLE_RATE"])
                if not 1 <= maximum <= 32 or not 8000 <= rate <= 192000:
                    raise ValueError("invalid capabilities")
                caps = set(fields["CAPS"].split(","))
            except (KeyError, ValueError):
                self.log.emit("提示", "设备握手字段无效，继续等待")
                return
            self.handshake_timer.stop()
            self.ready = True
            self.device = fields
            self.capabilities = caps
            self.label = "模拟设备 · 不产生声音" if self.simulated else "设备已确认"
            if "STATUS" in caps:
                self.poll.start()
                self.query_status()
        elif line.startswith("APPLIED "):
            if self.pending and line == f"APPLIED {self.pending[0]}":
                self.applied = self.pending[1]
                self.pending = None
                self.apply_timer.stop()
                self.log.emit("提示", "模拟设备已确认配置" if self.simulated else "设备已确认配置")
            else:
                self.log.emit("提示", "忽略不匹配的配置确认")
        elif line.startswith("ERROR "):
            fields = line.split(" ", 2)
            if fields == ["ERROR", "0", "NOT_READY"]:
                self.ready = False
                self.poll.stop()
                self.label = "设备会话已失效 · 请断开后重连"
                self.log.emit("提示", "设备要求重新HELLO；请断开后重连，避免重放旧按键")
            if self.pending and len(fields) == 3 and fields[1] == str(self.pending[0]):
                self.pending = None
                self.apply_timer.stop()
                self.log.emit("提示", "配置被设备拒绝：" + fields[2])
        elif line.startswith("STATUS ") and self.ready:
            values = {}
            for item in line.split()[1:]:
                try:
                    key, value = item.split("=", 1)
                    if key in {"VOICE_COUNT", "MAX_VOICE_COUNT", "STEAL_COUNT", "SAMPLE_RATE"}:
                        value = int(value)
                        if value >= 0:
                            values[key] = value
                except ValueError:
                    continue
            self.status.update(values)
            self.status_changed.emit(dict(self.status))
        self.changed.emit()

    @Slot(int, int)
    def _traffic(self, tx, rx):
        if self.sender() is self.transport:
            self.tx_bytes += tx
            self.rx_bytes += rx
            self.changed.emit()

    @Slot(str)
    def _error(self, message):
        if self.sender() is self.transport:
            self.log.emit("错误", message)
            self.disconnect_device()

    @Slot()
    def _closed(self):
        if self.sender() is self.transport:
            self._reset()

    def _reset(self):
        old_transport = self.transport
        self.handshake_timer.stop()
        self.apply_timer.stop()
        self.poll.stop()
        self.transport = None
        self.ready = False
        self.capabilities.clear()
        self.device = {}
        self.status = {}
        self.applied = self.pending = None
        self.label = "未连接"
        self.status_changed.emit({})
        self.changed.emit()
        if old_transport is not None:
            old_transport.deleteLater()

    def disconnect_device(self):
        if self.transport is not None:
            # 尽力释放PC声部；断线/队列满时仍关闭，FPGA看门狗独立兜底。
            try:
                self.panic()
            except (RuntimeError, OSError) as exc:
                self.log.emit("提示", f"停止命令未能发送：{exc}；设备由失联保护释放")
            self.transport.close()
            if self.transport is not None:
                self._reset()

    def _handshake_timeout(self):
        self.label = "串口已打开 · 固件未响应"
        self.log.emit("提示", "未收到 SYNTH/1 握手。当前 FPGA 程序可能尚无串口控制功能。")
        self.changed.emit()

    def _apply_timeout(self):
        self.pending = None
        self.log.emit("提示", "配置确认超时；设备状态未知，请重连后重新应用")
        # The device may have applied the packet but lost its reply.
        self.applied = None
        self.changed.emit()

    def query_status(self):
        if self.ready and "STATUS" in self.capabilities:
            try:
                self.send("STATUS?")
            except RuntimeError as exc:
                self.log.emit("错误", str(exc))

    @property
    def fixed_sine(self):
        return self.fixed_tone and self.device.get("TONE") == "FIXED_SINE"

    @property
    def fixed_tone(self):
        # 白名单，而非任意TONE字段都绕过配置确认；模拟CONFIG设备仍须APPLY。
        return (self.ready and {"NOTES", "STATUS"} <= self.capabilities
                and "CONFIG" not in self.capabilities
                and self.device.get("TONE") in {"FIXED_SINE", "FIXED_PIANO"})

    @property
    def fixed_tone_name(self):
        return {"FIXED_SINE": "正弦", "FIXED_PIANO": "钢琴感"}.get(self.device.get("TONE"), "未知")

    @property
    def playable(self):
        # 固定音色是真实设备能力，不生成虚假的applied配置对象。
        return (self.ready and "NOTES" in self.capabilities
                and (self.fixed_tone or self.applied is not None))

    def note(self, note, on):
        if not self.playable:
            raise RuntimeError("先连接支持演奏的设备并应用音色")
        if type(note) is not int or not 0 <= note <= 127:
            raise ValueError("音符范围为 0～127")
        self.send(f"NOTE_ON {note} 100 0" if on else f"NOTE_OFF {note} 0")

    def panic(self):
        if self.ready and "NOTES" in self.capabilities:
            self.send("PANIC")
