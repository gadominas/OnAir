# OnAir

**A live agenda, stage screen and speaker timer for single-track events, driven by one JSON file.**

OnAir shows attendees what's on stage right now, keeps the room screen in sync with the schedule, and gives
speakers a countdown they can't miss. When the day doesn't go to plan, you fix the schedule from a small
local admin page and every screen follows within seconds.

No build step, no framework, no database: three static HTML pages, one `agenda.json`, and an optional
zero-dependency Node.js server for editing on the day. It was first used at a one-day tech conference, where
talks were added, moved and re-timed live without anyone in the audience noticing.

**Demo:** https://gadominas.github.io/OnAir/ (try `?sim=09:30`, and press `P` for presentation mode)

![Presentation mode on a shared screen](docs/presentation.png)

## What's in the box

| Screen | For | What it does |
|---|---|---|
| **Live agenda** (`index.html`) | Attendees, on phones and laptops | Countdown before the event, what's on stage now with a progress bar, what's next, the full agenda grouped into acts, "Ask a question", the livestream link. |
| **Presentation mode** (`index.html`, press `P`) | The audience, on a projector or TV | The big version: current talk, a large clock, a "scan to ask" QR code, the next sessions, and an animated terminal prompt that loops between talks and stays still while someone is on stage. |
| **Stage screen** (`stage.html`) | The room | Agenda on the left and your Q&A tool (for example Slido) on the right. The Q&A panel takes 40% during a talk, grows to 70% with a countdown during Q&A, and hides during breaks. |
| **Speaker timer** (`timer.html`) | The speaker, on a confidence monitor | A huge countdown that turns amber at 5 min, orange at 2 and red in the last minute, then blinks **STOP** when talk time is up and counts down the Q&A. |
| **Admin** (`admin/`) | The organiser, on their laptop | Edit, drag to reorder, and re-time sessions. **"Start it now"** shifts the rest of the day when a talk starts late. It saves to `agenda.json` and can publish to GitHub Pages. |

| Live agenda | Stage screen during Q&A |
|---|---|
| ![Live agenda](docs/agenda.png) | ![Stage screen during Q&A](docs/stage-qa.png) |
| **Speaker timer, 5 minutes left** | **Speaker timer, talk time is up** |
| ![Speaker timer](docs/timer-5min.png) | ![Stop alarm](docs/timer-stop.png) |

![Admin and live control](docs/admin.png)

## Quick start

You need [Node.js](https://nodejs.org) 18 or newer, and nothing else: there are no npm packages to install.
`./onair.sh setup` checks this and, if Node.js (or `lsof`, which the script uses) is missing, offers to install it
with Homebrew on macOS or your Linux package manager. `start` runs the same check automatically.

```bash
git clone https://github.com/gadominas/OnAir.git
cd OnAir
./onair.sh start        # or: node admin/server.mjs (foreground)
```

Run `./onair.sh` on its own for a small menu: start, stop, restart, status, logs, open the admin, agenda,
stage or timer in your browser, change the port, and check prerequisites. The commands also work directly:
`./onair.sh start | stop | restart | status | logs | run | setup`. The server runs in the background, so it keeps
going when you close the menu. If another program already holds the port, OnAir asks whether to stop it.
In scripts or CI, `ONAIR_KILL=1` answers that question with yes, and `ONAIR_YES=1` installs prerequisites without asking. Settings such as `PORT=8080 ./onair.sh start` pass through to the server.

| Open | |
|---|---|
| http://localhost:4242/ | Live agenda (press `P` for presentation mode) |
| http://localhost:4242/stage.html | Stage screen |
| http://localhost:4242/timer.html | Speaker timer |
| http://localhost:4242/admin/ | Admin (only from this computer) |

The demo agenda is set on a future date, so to see it live, pretend it's a moment on the event day:
http://localhost:4242/?sim=09:30 (add `&speed=10` to watch time run faster). Every page accepts this.

## Make it your event

1. **Edit `agenda.json`**, by hand or in the admin. Set your event's name, date, time zone, sessions and links. The reference is below.
2. **Rehearse** any moment with `?sim=HH:MM`, or with the "Test the live view" button in the agenda's footer.
3. **Publish** the agenda for attendees on any static host. With GitHub Pages:
   - Fork or push this repository to GitHub.
   - In **Settings → Pages → Build and deployment**, set **Source** to **GitHub Actions**. The included workflow deploys every push to `main`.
   - Your agenda is then at `https://<you>.github.io/<repo>/`.

### On the day

- **Run the room screens from your laptop** with `./onair.sh start`. Screens on the venue network open the stage and timer pages at the network address the server prints (for example `http://192.168.1.20:4242/stage.html`). They read your local `agenda.json`, so changes reach them within seconds, with no deploy. Other devices get read-only access; the admin page and its API only answer on the laptop itself.
- **Re-time from the admin.** If a speaker isn't ready, press **"Started late? Start it now"** when they begin. That session moves to the current minute and everything after it shifts. Tick **"Catch up"** to take the delay out of the next break instead.
- **Publish** pushes `agenda.json` to GitHub (commit, pull with rebase, push), and open attendee pages pick the change up on their own. Batch edits rather than publishing after every small change, since each publish triggers a deploy.

## `agenda.json`

```jsonc
{
  "event": {
    "name": "OnAir Demo Day 2027",
    "brand": { "title": "OnAir", "number": "Demo" },   // header wordmark; "number" is optional
    "city": "Lisbon",
    "date": "2027-05-20",                             // the event day
    "timeZone": "Europe/Lisbon",                      // for displaying times
    "utcOffset": "+01:00",                            // the offset on that day (mind daylight saving)
    "timeZoneNote": "Lisbon time (WEST, UTC+1)",
    "venue": "Example Hall, Rua do Exemplo 42, Lisbon.",
    "dateText": "Thursday 20 May 2027",
    "organizer": "Your Organisation"
  },
  "links": {                     // all optional; an empty link hides its buttons
    "qa": "",                    // "Ask a question" buttons + the presentation-mode QR code
    "qrUrl": "",                 // optional: a different (e.g. shorter) URL for the QR code
    "wall": "",                  // the stage screen's Q&A panel (must allow embedding)
    "stream": ""                 // "Watch the livestream"
  },
  "theme": { "ink": "#0F0F46", "navy": "#2A2A72", "accent": "#3ACEA9", "accentInk": "#0E7A5E" },
  "labels": { "act": "Act" },    // the word before act numbers ("Track", "Part", …)
  "cli": {                       // the animated prompt in the live agenda (still while someone is on stage); all optional
    "command": "onair --city",
    "guesses": ["porto", "madrid", "paris"],   // typed and deleted before the answer
    "answer": "lisbon",                        // default: the city in lowercase
    "jokes": true,                             // true = 42 built-in joke commands, false = none, or your own list
    "exitCode": 0,
    "enabled": true
  },
  "timing": { "talkMinutes": 35, "qaMinutes": 7, "changeoverMinutes": 5 },
  "acts": { "1": "Faster, smaller, clearer", "2": "Shipping it" },
  "sessions": [
    { "start": "09:00", "dur": 10, "kind": "keynote", "title": "Opening", "who": "Rita Moreno-Lind", "role": "Host" },
    { "start": "09:10", "dur": 42, "kind": "talk", "act": 1, "title": "The Latency Budget",
      "who": "Tomas Varga", "role": "Platform Engineer", "desc": "One or two sentences." },
    { "start": "10:39", "dur": 10, "kind": "break", "title": "Coffee break" },
    { "start": "12:23", "dur": 20, "kind": "talk", "act": 2, "title": "Lightning talk", "qa": 5 }
  ]
}
```

| Session field | Notes |
|---|---|
| `start`, `dur` | `"HH:MM"` in the event's local time, and minutes. |
| `kind` | `talk`, `break` or `keynote`. Breaks are titled exactly `Coffee break` or `Lunch` (that picks the icon and labels). |
| `qa` | Talks only. Q&A minutes at the end of the slot; the talk part is the rest. Defaults to `timing.qaMinutes`, so a 42-minute talk is 35 + 7 and a 20-minute talk is 13 + 7. |
| `act` | Talks only. Groups talks under an act heading from `acts`. |
| `who`, `role`, `desc` | Speaker, their role or team, and a short description. |

**Scheduling convention.** Sessions follow each other back to back, with a changeover (`timing.changeoverMinutes`)
after a talk unless a break comes next. The changeover isn't a session; it exists only as the gap between start
times, and the screens show "Up next" with a countdown during it. The admin keeps this for you. When editing by
hand, the checks in [AGENTS.md](AGENTS.md) tell you whether the times still line up.

## URL parameters

| Parameter | Pages | Effect |
|---|---|---|
| `sim=HH:MM[:SS]` | all | Pretend it's that time on the event day (the agenda page also takes `YYYY-MM-DDTHH:MM`). |
| `speed=N` | all | Run the simulated clock N times faster. |
| `quiet` | all | Hide the "test mode" banner (demos, screenshots). |
| `agenda=<url>` | all | Load a different agenda file. |
| `mode=present` | agenda | Open straight into presentation mode. |
| `slido=qa` | stage | Show the Q&A panel only during Q&A, not during the whole talk. |
| `wall=<url>` | stage | Use a different Q&A page than `links.wall`. |

## Keyboard

| Key | Where | Action |
|---|---|---|
| `P` | agenda | Presentation mode on/off |
| `F` | presentation, stage, timer | Full screen |
| `A` / `S` / `H` | stage | Q&A panel automatic / always show / always hide |
| `R` | stage | Reload the Q&A panel |
| `⌘Z` / `⇧⌘Z` | admin | Undo / redo |

## Q&A tools

The stage screen and the "Ask a question" dialog embed whatever page you link, as long as that page allows
embedding. With **Slido**, use the event's audience link, `https://app.sli.do/event/<event-id>`, which needs no
login (click "Join anonymously" once on the stage computer). Slido's host views (`admin.sli.do` and the
Present-mode wall) refuse to be embedded in other sites, so they can't be used in the panel.

## How it works

Every page fetches `agenda.json` from the host that serves it and works out its whole state (what's on, what's
next, how long is left) from the clock and the agenda several times a second. Pages poll for changes and
update in place or reload themselves, so the same files work on GitHub Pages, any static host, or the local
server. [docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md) covers the architecture, the data model, the admin's
re-timing logic, and the security model of the local server.

## Configuration of the local server

```bash
PORT=8080 node admin/server.mjs              # another port (default 4242)
HOST=127.0.0.1 node admin/server.mjs         # don't expose anything to the network
AGENDA_FILE=events/day2.json node admin/server.mjs
BRANCH=main REMOTE=origin node admin/server.mjs   # where Publish pushes (default: current branch, origin)
```

## License

[MIT](LICENSE). `vendor/qrcode.mjs` is [QR Code Generator](https://github.com/kazuhikoarase/qrcode-generator)
by Kazuhiko Arase, also MIT licensed.
