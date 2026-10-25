# Lango design contract

Mission: a quiet, Chinese-first practice room that makes speaking English feel safe, focused, and intentional. This is a real connected client; there are no fabricated conversations, completion statistics, or AI responses.

## Tokens
- Canvas warm stone #F4F2ED; surface ivory #FCFBF8; recessed #ECEAE4.
- Ink #252C29; secondary #6F7771; primary deep teal #285E52; mint #DCEAE2; danger #A44136.
- Dark canvas #191E1B; surface #222925; raised #2B342E; ink #EEEFE7; teal #A8D1BD.
- System CJK sans with generous 1.5 line-height; editorial serif English display, not for controls. Display 36–52, heading 24–28, body 16, metadata 12–14. Timers use tabular figures.
- 4px rhythm, 8/16/24/32/48 spacing; controls at least 48px tall; cards radius 24; inputs 16; pill actions 999.
- Structural state changes 180–240ms ease-out; orb responds to actual microphone RMS / playback state, not decorative idle motion. Reduced motion freezes shape changes and removes transition duration.

## Do / don't
- Use tonal separation, restrained cards, ample negative space, semantic Material controls and visible focus states.
- Keep actions clear, loading bounded, errors actionable, empty states honest. Wrap at narrow widths; preserve readable maximum widths on desktop.
- Never put tokens in URLs, ACK unheard audio, replay uncommitted inputs, or present energy-threshold detection as neural VAD.
- No garish gradients, fake streaks, fake providers, or giant marketing feature grid.

## Assumptions
- Server URL is user supplied, has no path/query, and hosts protocol v1 at /api/v1.
- Engine preference, theme and reduced motion are device-local. Voice, speed, memory and profile are server-backed. Engine availability comes exclusively from /config.
- Automatic speech modes use explicitly labelled energy-based VAD, half-duplex playback, a 200ms pre-roll, roughly 900ms silence endpoint, and a 60-second maximum. Microphone capture resumes only after generated audio has drained. Interrupting is explicit.
- Web microphone access and secure storage require HTTPS or localhost. LAN HTTP is for trusted Android development only; prefer HTTPS. No raw microphone audio is saved to disk.
