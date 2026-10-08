# AGENTS.md

Rules for people and AI agents editing an OnAir agenda (`agenda.json`) or the OnAir code.

## Layout

- `agenda.json`: the single source of truth for the event: details, links, theme, timing, acts and sessions.
- `index.html`, `timer.html`: static pages that fetch `agenda.json` from the host serving them.
  `?agenda=<url>` overrides the source.
- `admin/`: the local admin and server (`node admin/server.mjs`). It edits `agenda.json` and can publish it with git.
- `docs/IMPLEMENTATION.md`: architecture and implementation notes. Keep it in sync with behaviour changes.

Change the event in `agenda.json`, never in the HTML. Nothing event-specific belongs in the pages.

## Scheduling rules

- **Talks** (`"kind": "talk"`) end with Q&A. The Q&A is the last `qa` minutes of the slot (default `timing.qaMinutes`),
  and the talk part is the rest. A standard talk lasts `timing.talkMinutes + timing.qaMinutes` minutes, but any
  length works: a 20-minute talk with the default 7-minute Q&A is 13 + 7, or set `"qa": 5` for 15 + 5.
- **Breaks** (`"kind": "break"`) are titled exactly `"Coffee break"` or `"Lunch"`. The pages key off these titles
  for icons and labels.
- **Keynotes** (`"kind": "keynote"`) usually open and close the day. They have no Q&A.
- **Changeover after each talk:** `timing.changeoverMinutes` after a talk's Q&A, for the next speaker to get ready.
  It applies only when the next session isn't a break. **The changeover is never a session.** It exists only as the
  gap between two `start` times.
- **No other gaps, no overlaps.** Each session starts when the previous one ends, plus the changeover where it applies.
  The exception is on the day: if a session really started late, its later start (and everything after it) is expected.
- Sessions are listed in chronological order. The day starts with the first session's `start`.
- All times are `"HH:MM"` in the event's local time (`event.timeZone`, `event.utcOffset`), never UTC.

## Sessions

| Field   | Required for     | Notes                                                                 |
|---------|------------------|-----------------------------------------------------------------------|
| `start` | all              | `"HH:MM"` local event time                                            |
| `dur`   | all              | minutes (the changeover isn't included)                               |
| `kind`  | all              | `"talk"`, `"break"` or `"keynote"`                                    |
| `title` | all              | `"Coffee break"` / `"Lunch"` for breaks                               |
| `qa`    | optional, talks  | Q&A minutes at the end of the slot; omit to use `timing.qaMinutes`    |
| `act`   | talks, if `acts` | a key in `acts`; talks in an act are consecutive                      |
| `who`   | talks, keynotes  | speaker name(s); use `" & "` for two speakers                         |
| `role`  | optional         | speaker role or team                                                  |
| `desc`  | talks            | one or two plain sentences                                            |

## Event block

When the date changes, update `event.date`, `event.dateText` and `event.utcOffset` together. The offset has to match
daylight saving on that day.

## Links

`links.qa` and `links.stream` are optional; an empty link hides its buttons and panels. `links.qa` is the one Q&A
link: the Ask buttons (which open it in a new tab) and the presentation-mode QR code use it (for Slido, the audience link
`https://app.sli.do/event/<id>`). Change links in `agenda.json` or in the admin's "Links & QR code"
panel, which saves them through `PUT /api/links`; a general admin save always keeps the links on disk, so a stale admin
tab can't overwrite them.

## Check before committing

```bash
node -e '
const a=require("./agenda.json"),m=t=>{const[h,n]=t.split(":").map(Number);return h*60+n};
a.sessions.forEach((s,i)=>{const n=a.sessions[i+1],gap=n&&s.kind==="talk"&&n.kind!=="break"?a.timing.changeoverMinutes||0:0;
 if(s.kind==="talk"&&(s.qa??a.timing.qaMinutes)>=s.dur)console.log("Q&A fills the whole talk:",s.title);
 if(s.kind==="talk"&&a.acts&&!a.acts[s.act])console.log("unknown act:",s.title);
 if(s.kind==="break"&&!["Lunch","Coffee break"].includes(s.title))console.log("odd break title:",s.title);
 if(n&&m(s.start)+s.dur+gap!==m(n.start))console.log("unexpected gap/overlap after:",s.title)});
console.log("checked",a.sessions.length,"sessions")'
```

## Previewing

Run `node admin/server.mjs` and open http://localhost:4242/. Add `?sim=14:50` (any page) to see it as it would
look at that time on the event day, and `&speed=10` to run the clock faster. In the admin, "Pretend it's" and the speed next to it
(up to 300×, or paused) do the same, and the screens it opens follow that time and speed. "Start now" uses the pretend
time, so go back to real time before using it on the day.
