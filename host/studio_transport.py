"""Async serial transport, explicit device handshake, and a silent simulator."""
import queue
import threading
import time
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


class CommandQueue:
    """64 normal commands; bounded, deduplicated releases have reserved space.

    A release removes an unsent note-on for that pitch before moving ahead of
    diagnostics. Otherwise an early NOTE_OFF could be followed by a stale ON.
    PANIC/HELLO also cancel unsent musical events. An in-flight write finishes
    before the worker dequeues its next command, preserving wire order.
    """
    def __init__(self):
        self.items = deque()
        self.lock = threading.Lock()

    def put_nowait(self, payload):
        parts = payload.split()
        command = parts[0]
        with self.lock:
            if command in {b"PANIC", b"HELLO"}:
                self.items = deque(p for p in self.items if p.split()[0] not in
                                   {b"NOTE_ON", b"NOTE_OFF", b"PANIC", b"HELLO"})
                self.items.appendleft(payload)
            elif command == b"NOTE_OFF":
                note = parts[1]
                self.items = deque(p for p in self.items if not
                                   (p.split()[0] in {b"NOTE_ON", b"NOTE_OFF"} and p.split()[1] == note))
                self.items.appendleft(payload)
            else:
                normal = sum(p.split()[0] not in {b"NOTE_OFF", b"PANIC", b"HELLO"} for p in self.items)
                if normal >= 64:
                    raise queue.Full
                self.items.append(payload)

    def get_nowait(self):
        with self.lock:
            if not self.items:
                raise queue.Empty
            return self.items.popleft()


class SerialTransport(QThread):
    opened = Signal()
    line = Signal(str)
    error = Signal(str)
    closed = Signal()
    traffic = Signal(int, int)

    def __init__(self, port, baud, parent=None):
        super().__init__(parent)
        self.port, self.baud = port, baud
        self.outbound = CommandQueue()
        self.wakeup = threading.Event()

    def send(self, text):
        if self.isInterruptionRequested():
            raise RuntimeError("串口正在关闭")
        try:
            self.outbound.put_nowait((text + "\n").encode("ascii"))
            self.wakeup.set()
        except queue.Full:
            raise RuntimeError("发送队列繁忙；停止命令仍可发送，请稍候") from None

    def run(self):
        import serial
        try:
            with serial.Serial(self.port, self.baud, timeout=0,
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
                    # Never wait for an unsolicited reply between chord notes.
                    available = min(port.in_waiting, 256)
                    data = port.read(available) if available else b""
                    if data:
                        self.traffic.emit(0, len(data))
                        for line in decoder.feed(data):
                            self.line.emit(line)
                    if payload is None and not data:
                        self.wakeup.wait(.002)
                        self.wakeup.clear()
        except Exception as exc:
            self.error.emit(str(exc))
        finally:
            self.closed.emit()

    def close(self):
        self.requestInterruption()
        self.wakeup.set()
        # Read/write timeouts bound shutdown; never destroy a running QThread.
        if not self.wait(1500):
            raise RuntimeError("串口线程仍在退出，请稍后再关闭窗口")


class MockTransport(QObject):
    opened = Signal()
    line = Signal(str)
    error = Signal(str)
    closed = Signal()
    traffic = Signal(int, int)

    def __init__(self, parent=None, piano=False):
        super().__init__(parent)
        self.piano = piano
        self.maximum = 16 if piano else 4
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
            self.notes.clear()
            self.reply("SYNTH/1 CAPS=NOTES,STATUS MAX_VOICES=16 SAMPLE_RATE=48000 FW=host-simulator TONE=FIXED_PIANO"
                       if self.piano else "SYNTH/1 CAPS=CONFIG,NOTES,STATUS MAX_VOICES=4 SAMPLE_RATE=48000 FW=simulator")
        elif text.startswith("APPLY "):
            if self.piano:
                self.reply(f"ERROR {fields[1]} UNSUPPORTED")
                return
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
            if len(self.notes) == self.maximum:
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
        self.selected_preset = None
        self.preset_pending = None
        self.controls = self.controls_pending = None
        self.control_timer = QTimer(self)
        self.control_timer.setSingleShot(True)
        self.control_timer.timeout.connect(self._control_timeout)
        self.sequence = 0
        self.tx_bytes = self.rx_bytes = 0
        self.active_notes = set()
        self.pending_releases = set()
        self.panic_pending = False
        self.last_response = None
        self.retry_timer = QTimer(self)
        self.retry_timer.setInterval(40)
        self.retry_timer.timeout.connect(self._retry_stops)
        self.handshake_timer = QTimer(self)
        self.handshake_timer.setSingleShot(True)
        self.handshake_timer.timeout.connect(self._handshake_timeout)
        self.apply_timer = QTimer(self)
        self.apply_timer.setSingleShot(True)
        self.apply_timer.timeout.connect(self._apply_timeout)
        self.preset_timer = QTimer(self)
        self.preset_timer.setSingleShot(True)
        self.preset_timer.timeout.connect(self._preset_timeout)
        self.poll = QTimer(self)
        self.poll.setInterval(1000)
        self.poll.timeout.connect(self.query_status)

    def connect_device(self, port, baud=115200, transport=None):
        if self.transport is not None:
            raise RuntimeError("请先断开当前设备")
        self.simulated = port in {"SIM", "SIM_PIANO"}
        self.label = "正在连接…"
        self.tx_bytes = self.rx_bytes = 0
        self.transport = transport or (MockTransport(self, piano=port == "SIM_PIANO") if self.simulated else
                                      SerialTransport(port, baud, self))
        self.transport.opened.connect(self._opened)
        self.transport.line.connect(self._line)
        self.transport.error.connect(self._error)
        # QThread.finished, unlike a signal emitted inside run(), guarantees
        # that deleteLater cannot destroy a still-running native worker.
        (self.transport.finished if isinstance(self.transport, QThread) else self.transport.closed).connect(self._closed)
        self.transport.traffic.connect(self._traffic)
        self.changed.emit()
        self.transport.start()

    @Slot()
    def _opened(self):
        if self.sender() is not self.transport:
            return
        self.label = "串口已打开，等待设备确认…"
        self.handshake_timer.start(1800)
        self.send("HELLO")
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

    def select_preset(self, preset):
        if not self.factory_presets:
            raise RuntimeError("设备未确认支持钢琴／摇滚预设")
        if type(preset) is not int or preset not in (0, 1):
            raise ValueError("预设只能为 0（摇滚）或 1（钢琴）")
        if self.preset_pending is not None:
            raise RuntimeError("正在等待设备确认音色")
        self.preset_pending = preset
        try:
            self.send(f"PRESET {preset}")
        except Exception:
            self.preset_pending = None
            raise
        self.preset_timer.start(1800)
        self.changed.emit()

    @property
    def performance_controls(self):
        return self.factory_presets and "CONTROL" in self.capabilities

    def set_controls(self, volume, bend):
        if not self.performance_controls or self.controls is None:
            raise RuntimeError("设备尚未确认音量／弯音控制状态")
        if type(volume) is not int or not 0 <= volume <= 127 or type(bend) is not int or not 0 <= bend <= 1024:
            raise ValueError("音量范围0～127，弯音码0～1024，中心512")
        if self.controls_pending is not None:
            raise RuntimeError("正在等待设备确认演奏控制")
        self.controls_pending = (volume, bend)
        try:
            self.send(f"CONTROL {volume} {bend}")
        except Exception:
            self.controls_pending = None
            raise
        self.control_timer.start(1800)
        self.changed.emit()

    def _control_timeout(self):
        self.control_timer.stop()
        self.controls = self.controls_pending = None
        self.log.emit("提示", "演奏控制确认超时；等待完整设备状态，未自动重发")
        self.query_status()
        self.changed.emit()

    def _preset_timeout(self):
        self.preset_timer.stop()
        self.preset_pending = None
        self.selected_preset = None
        self.log.emit("提示", "音色确认超时；等待设备状态后再演奏")
        self.query_status()
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
            self.last_response = time.monotonic()
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
                self._invalidate("设备会话已失效 · 请重新握手")
            if self.pending and len(fields) == 3 and fields[1] == str(self.pending[0]):
                self.pending = None
                self.apply_timer.stop()
                self.log.emit("提示", "配置被设备拒绝：" + fields[2])
            if self.preset_pending is not None and len(fields) == 3 and fields[1] == "0":
                self.preset_timer.stop()
                self.selected_preset = self.preset_pending = None
                self.log.emit("提示", "音色请求被拒绝：" + fields[2])
                self.query_status()
            if self.controls_pending is not None and len(fields) == 3 and fields[1] == "0":
                self.control_timer.stop()
                self.controls = self.controls_pending = None
                self.log.emit("提示", "演奏控制请求被拒绝：" + fields[2])
                self.query_status()
        elif line.startswith("STATUS ") and self.ready:
            values = {}
            for item in line.split()[1:]:
                try:
                    key, value = item.split("=", 1)
                    ranges = {"VOICE_COUNT": (0, 32), "MAX_VOICE_COUNT": (0, 32),
                              "STEAL_COUNT": (0, 4294967295), "SAMPLE_RATE": (8000, 192000)}
                    if key in ranges:
                        value = int(value)
                        if ranges[key][0] <= value <= ranges[key][1]:
                            values[key] = value
                    elif key in {"VOLUME", "BEND"} and self.performance_controls:
                        limit = 127 if key == "VOLUME" else 1024
                        if value.isascii() and value.isdigit() and 0 <= int(value) <= limit:
                            values[key] = int(value)
                    elif key == "PRESET" and self.factory_presets and value in {"0", "1"}:
                        values[key] = int(value)
                except ValueError:
                    continue
            self.status.update(values)
            if "PRESET" in values:
                self.selected_preset = values["PRESET"]
                if self.preset_pending == self.selected_preset:
                    self.preset_pending = None
                    self.preset_timer.stop()
            # A pair must arrive in one status line; never combine partial/stale reports.
            if "VOLUME" in values and "BEND" in values:
                self.controls = (values["VOLUME"], values["BEND"])
                if self.controls == self.controls_pending:
                    self.controls_pending = None
                    self.control_timer.stop()
            if values:
                self.last_response = time.monotonic()
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
        self.preset_timer.stop()
        self.control_timer.stop()
        self.controls = self.controls_pending = None
        self.poll.stop()
        self.retry_timer.stop()
        self.active_notes.clear()
        self.pending_releases.clear()
        self.panic_pending = False
        self.last_response = None
        self.transport = None
        self.ready = False
        self.capabilities.clear()
        self.device = {}
        self.status = {}
        self.applied = self.pending = None
        self.selected_preset = self.preset_pending = None
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
        self.log.emit("提示", "未收到 SYNTH/1 握手；核对UART串口、115200波特率与已下载固件，再重新握手。")
        self.changed.emit()

    def _apply_timeout(self):
        self.pending = None
        self.log.emit("提示", "配置确认超时；设备状态未知，请重连后重新应用")
        # The device may have applied the packet but lost its reply.
        self.applied = None
        try:
            self.panic()
        except RuntimeError:
            pass  # retry_timer retains the stop request.
        self.changed.emit()

    def query_status(self):
        if self.ready and "STATUS" in self.capabilities:
            if self.last_response is not None and time.monotonic() - self.last_response > 3:
                try:
                    self.panic()
                except RuntimeError:
                    pass
                self._invalidate("状态回复超时 · 请重新握手")
                return
            try:
                self.send("STATUS?")
            except RuntimeError as exc:
                self.log.emit("错误", str(exc))

    def _invalidate(self, reason):
        # Stop heartbeats as well as new notes; the FPGA's independent session
        # watchdog can then recover PC voices if the stop packet cannot arrive.
        self.ready = False
        self.poll.stop()
        self.apply_timer.stop()
        self.retry_timer.stop()
        self.preset_timer.stop()
        self.control_timer.stop()
        self.selected_preset = self.preset_pending = None
        self.controls = self.controls_pending = None
        self.applied = self.pending = None
        self.active_notes.clear()
        self.pending_releases.clear()
        self.panic_pending = False
        self.status.clear()
        self.status_changed.emit({})
        self.label = reason
        self.log.emit("提示", reason + "；不自动重放按键，必要时由设备失联保护释放电脑声部。")
        self.changed.emit()

    def rehandshake(self):
        if self.transport is None:
            raise RuntimeError("请先连接串口")
        self._invalidate("等待设备重新确认…")
        self.handshake_timer.start(1800)
        self.send("HELLO")

    def _retry_stops(self):
        if not self.ready:
            self.retry_timer.stop()
            return
        try:
            if self.panic_pending:
                self.panic()
            else:
                for note in list(self.pending_releases):
                    self.note(note, False)
        except RuntimeError:
            return
        if not self.pending_releases and not self.panic_pending:
            self.retry_timer.stop()

    @property
    def fixed_sine(self):
        return self.fixed_tone and self.device.get("TONE") == "FIXED_SINE"

    @property
    def fixed_tone(self):
        # 白名单，而非任意TONE字段都绕过配置确认；模拟CONFIG设备仍须APPLY。
        return (self.ready and {"NOTES", "STATUS"} <= self.capabilities
                and "CONFIG" not in self.capabilities
                and self.device.get("TONE") in {"FIXED_SINE", "FIXED_PIANO", "PIANO_GUITAR"})

    @property
    def fixed_tone_name(self):
        return {"FIXED_SINE": "正弦", "FIXED_PIANO": "钢琴感",
                "PIANO_GUITAR": "钢琴／吉他（KEY2切换）"}.get(self.device.get("TONE"), "未知")

    @property
    def factory_presets(self):
        return (self.ready and {"NOTES", "STATUS", "PRESET"} <= self.capabilities
                and "CONFIG" not in self.capabilities
                and self.device.get("TONE") == "PIANO_ROCK")

    @property
    def preset_name(self):
        return {0: "摇滚电吉他", 1: "钢琴"}.get(self.selected_preset, "等待设备确认")

    @property
    def playable(self):
        # 固定音色是真实设备能力，不生成虚假的applied配置对象。
        return (self.ready and "NOTES" in self.capabilities
                and self.pending is None and not self.panic_pending
                and (self.fixed_tone or self.applied is not None or
                     (self.factory_presets and self.selected_preset is not None
                      and self.preset_pending is None)))

    def note(self, note, on):
        if not self.ready or "NOTES" not in self.capabilities or on and not self.playable:
            raise RuntimeError("先连接支持演奏的设备并应用音色")
        if type(note) is not int or not 0 <= note <= 127:
            raise ValueError("音符范围为 0～127")
        if on and note in self.pending_releases:
            raise RuntimeError("该音符正在释放，请稍候")
        try:
            self.send(f"NOTE_ON {note} 100 0" if on else f"NOTE_OFF {note} 0")
        except RuntimeError:
            if not on:
                self.pending_releases.add(note)
                self.retry_timer.start()
            raise
        if on:
            self.active_notes.add(note)
        else:
            self.active_notes.discard(note)
            self.pending_releases.discard(note)
        self.changed.emit()

    def panic(self):
        if self.ready and "NOTES" in self.capabilities:
            self.panic_pending = True
            try:
                self.send("PANIC")
            except RuntimeError:
                self.retry_timer.start()
                self.changed.emit()
                raise
            self.active_notes.clear()
            self.pending_releases.clear()
            self.panic_pending = False
            self.changed.emit()
