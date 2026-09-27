"""Simple text protocol used between the desktop tool and FPGA B/UART."""
import re


def status_command():
    return "STATUS?"


def test_command(voice_count):
    return f"TEST {int(voice_count)}"


def clear_command():
    return "CLEAR"


def note_on_command(note, velocity=100, source_id=0):
    return f"NOTE_ON {int(note)} {int(velocity)} {int(source_id)}"


def note_off_command(note, source_id=0):
    return f"NOTE_OFF {int(note)} {int(source_id)}"


def timbre_command(timbre_id):
    return f"TIMBRE {int(timbre_id)}"


def adsr_command(attack, decay, sustain, release):
    return f"ADSR {int(attack)} {int(decay)} {int(sustain)} {int(release)}"


def volume_command(value):
    return f"VOLUME {int(value)}"


def effect_command(name, value):
    return f"FX {str(name).upper()} {int(value)}"


def parse_status(text):
    result = {}
    for key, value in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(-?\d+)", text):
        result[key.upper()] = int(value)
    return result


def format_status(status):
    if not status:
        return ""
    keys = [
        "VOICE_COUNT", "MAX_VOICE_COUNT", "NOTE_ON_COUNT",
        "NOTE_OFF_COUNT", "STEAL_COUNT", "SAMPLE_RATE"
    ]
    return " ".join(f"{k}={status.get(k, 0)}" for k in keys)