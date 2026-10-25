# Macropad configuration protocol

Keyflow configures USB device `1189:8890` using interface 1's 64-byte interrupt OUT endpoint
`0x02`. This is a raw vendor configuration channel, not a HID report. Keyflow uses the bundled
libusb shared library to claim interface 1 and send packets to endpoint `0x02` in order; the library
is dynamically loaded from the app bundle.

Every packet is 64 bytes: report marker `03`, payload bytes, then zero padding. A slot binding sends
`a1 01` to select layer 1, the binding payload, and `aa aa` to commit. Slot IDs are 1–6 for keys
1–6 and 13–15 for knob left, press, and right.

For keyboard actions, payload is `slot 11 count index modifiers key`. Index 0 carries the first
step's modifiers and key code 0; indexes 1 through count carry each keystroke. Media actions use
`slot 12 usage-low usage-high`; mouse actions use `slot 13 buttons dx dy wheel modifiers`. LED mode
uses `b0 18 mode`, committed with `aa a1`.

The pad has no configuration readback command. Keyflow therefore applies all nine slots when it
does not have a known successfully applied state, then writes only changed slots on later profile
switches. A failed packet makes the saved state unknown, so the next attempt is a full application.
An absent slot is cleared by sending an empty keystroke (one step with zero modifiers and key code
zero), matching the existing `macropad` CLI implementation. That clear behavior has not yet been
verified on hardware, so bundled profiles should define every slot whenever possible.

This packet format and endpoint selection are carried forward from the existing `macropad` tool's
protocol notes and implementation, which were validated against the vendor utility and the physical
device. Writes are serialized; rapid focus changes are coalesced around the latest requested
profile. Keyflow persists a state only after every packet in that application succeeds.
