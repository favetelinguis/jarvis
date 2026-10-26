---
name: jarvis-design
description: Design rules for the Jarvis board (the web UI the human reads). Use whenever you change how the board looks, how a page or section is structured, how a widget explains itself, what the reader can adjust, or any text the board itself shows (headings, buttons, messages, the Guide). Gives the shared floor (WCAG 2.2 AA in measurable form), task type parity, four layers applied in order (Diátaxis, COGA, Mayer, Floe), and a page review checklist to answer item by item before delivery.
---

# Jarvis design

The board is read by one human who steers agents and reviews dense,
agent-written pages. Every rule below exists to make those pages easier to
read, act on, and trust. This skill is self-contained: every rule and check it
refers to is in this directory, it needs no other skill, and it fetches nothing
from the network.

Rules are design principles, not code. Each rule has an id and a check
question. A rule is met when its check question can be answered "yes" for the
page in front of you.

## How to apply

1. Before changing the board, read **Shared rules** and the section of every
   layer your change touches.
2. Make the change.
3. Review every page you changed against `references/checklist.md` (see
   **Review**).

The four layers are applied in this order, each on top of the ones before:

1. Diátaxis and plain language: which pages and sections exist, what each is
   for, how the board's own texts are written.
2. COGA: behaviour, orientation, and memory support.
3. Mayer and Cognitive Load Theory: how a widget explains its parts.
4. Floe: what the reader can adjust.

A later layer never breaks a rule of an earlier layer or of the floor. When
two rules seem to conflict, the earlier one wins and the later one finds
another way.

## Shared rules

### Floor (Grundnivå)

WCAG 2.2 AA in measurable form. Applies to every page and every layer.

| Id  | Rule                                                                                                                               | Check question                                                                                             |
| --- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| F1  | Text contrast is at least 4.5:1; large text (24px, or 18.66px bold) at least 3:1.                                                  | Does every text color on its background measure at least 4.5:1 (3:1 for large text)?                       |
| F2  | Every click or tap target is at least 24×24 CSS pixels, or has 24px of free space around it. Links inside running text are exempt. | Does every button, control, and stand-alone link measure at least 24×24?                                   |
| F3  | Focus is always visible, and never hidden behind sticky content.                                                                   | Tabbing through the page, can you always see where focus is?                                               |
| F4  | Everything works with the keyboard alone, in a sensible order, and focus can always leave.                                         | Can you reach and use every function with Tab, Shift+Tab, Enter, Space, and arrows, without getting stuck? |
| F5  | At 320 CSS pixels wide the page does not scroll sideways. Only diagrams and code blocks may scroll, inside their own frame.        | At 320px, is the page free of horizontal scrolling?                                                        |
| F6  | Status is never shown by color alone: a word, a shape, or an icon with a text alternative says the same.                           | Would the page still say every status in grayscale?                                                        |
| F7  | When the reader asks for reduced motion, nothing animates or slides.                                                               | With reduced motion on, does anything move?                                                                |
| F8  | Every page has one `h1`, a skip link to the main content, and landmarks (header, main navigation, main).                           | Does the page have one `h1`, a working skip link, and the three landmarks?                                 |
| F9  | Every form control has a visible label tied to it; errors name the field and say how to fix it.                                    | Does every control have a label, and does every error name its field?                                      |

### Task type parity

| Id  | Rule                                                                                                                                                                                                                                                                                                 | Check question                                                  |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- |
| P1  | With every task type (Feature, Research, PR review, Learn) agents and the human can still do what they could before the change: create a task, move it along its transitions, write its sections as widgets, read it, comment on a widget or a part of one, claim and release it, and show presence. | For each of the four types, does every one of these still work? |

Parity is about function, not looks or tool names.

### The shell

Every page is drawn by one shell (the app layout). It owns the skip link, the
main navigation, the breadcrumbs, and the main landmark. A page never draws
its own navigation.

## Layer 1: Diátaxis and plain language

Every page and every section of a task is exactly one of four forms, and is
written for that need. The reader knows what a page is for before reading it.
Which form each page and section has is listed in `references/diataxis.md`.

| Form        | Reader's need    | Written as                                     |
| ----------- | ---------------- | ---------------------------------------------- |
| Tutorial    | learn by doing   | the outcome, then steps in order, then a check |
| How-to      | get one job done | numbered action steps                          |
| Reference   | look up facts    | entries with the same fields in the same order |
| Explanation | understand why   | reasons and context, no steps                  |

| Id  | Rule                                                                                                                                                                                              | Check question                                                                       |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| D1  | Every page and every task section has exactly one form, shown as a text label.                                                                                                                    | Does the page, and each of its sections, show exactly one form label?                |
| D2  | A how-to shows numbered action steps without explanatory digressions, and links to the matching explanation.                                                                                      | Are the steps numbered actions only, with a link to the "why"?                       |
| D3  | A tutorial says first what the reader can do afterwards, then the steps in order, last a check of the result.                                                                                     | Is the order outcome, steps, check?                                                  |
| D4  | A reference gives every entry the same fields in the same order.                                                                                                                                  | Do all entries have the same fields in the same order?                               |
| D5  | An explanation gives reasons and context, and sends the reader to a how-to for steps.                                                                                                             | Is the page free of step lists the reader must follow?                               |
| D6  | The docs start page lists the four forms, one purpose per form on one line, each with a link.                                                                                                     | Does the start page list four forms, each with a one-line purpose and a link?        |
| D7  | The board's own texts (headings, buttons, messages, the Guide) use sentences of at most 20 words, in active voice. Button labels are verb phrases for the result ("Send comment", "Save colors"). | Is every sentence 20 words or fewer and active? Does every button start with a verb? |
| D8  | Running text stays under 80 characters per line, and the type scale has clear steps: page title, section heading, body, small print.                                                              | Are lines under 80 characters, and can you tell each heading level apart?            |
| D9  | Visual style never decides or changes a form. The form follows from the page's purpose, as listed in the reference file.                                                                          | Would the form label stay the same if the page were restyled?                        |

Texts agents write inside widgets are theirs; D7 covers only the board's own
texts.

## Layer 2: COGA

Behaviour, orientation, and memory support, after W3C's "Making Content
Usable for People with Cognitive and Learning Disabilities". The human reviews
dense, live-updating pages and must never lose their place or their work.

| Id  | Rule                                                                                                                                               | Check question                                                                                             |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| G1  | The main navigation is in the same place and the same order on every page.                                                                         | Is the main navigation identical in place and order on this page and the others?                           |
| G2  | Every page says where the human is (project, goal, task, and step) and which actions are possible next.                                            | Can you tell from the page alone where you are and what you can do next?                                   |
| G3  | An unsent comment or unsent quiz answers come back when the human leaves the page and returns in the same browser.                                 | Type, leave, come back: is the text still there?                                                           |
| G4  | A move of a task shows the from-step, the to-step, and what happens next, and happens only after a confirming click. One click never moves a task. | Does choosing a move ask for confirmation, with from, to, and next?                                        |
| G5  | A message stays on screen until the human closes it. Nothing dismisses itself.                                                                     | Does every message stay until you close it?                                                                |
| G6  | Every action is named in text. An icon is never the only name.                                                                                     | Does every button and link show a word?                                                                    |
| G7  | A live update never moves focus, the caret, or the scroll position, and marks in text what changed until the human has read it.                    | While you type, does an agent's change leave your text, caret, and scroll alone, and is the change marked? |
| G8  | Nothing the human does has a time limit.                                                                                                           | Can every step be done at any pace?                                                                        |

### Accessibility review

Review every changed page against WCAG 2.2 AA with the checklist in
`references/checklist.md`: keyboard, focus, and contrast at least. Check in a
browser (the Playwright MCP the project already uses works).

Add no motion or animation beyond what the task's requirements allow. A
transition that only decorates is not added.

## Layer 3: Mayer and Cognitive Load Theory

How a widget explains, after Mayer's multimedia principles and Sweller's
Cognitive Load Theory: the explanation sits next to what it explains, content
comes in parts, the part under discussion is marked, and nothing is there that
adds nothing. The human should understand an agent's explanation with less
effort.

| Id  | Rule                                                                                                                                                                                                                                                                                | Check question                                                                           |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| M1  | The explanation of a part of a diagram or architecture widget sits on the part, inside it or right next to it, inside the widget (spatial contiguity).                                                                                                                              | Can you read a part and its explanation without looking away from the part?              |
| M2  | A widget with more than one step (walkthrough, tour, quiz) shows one step at a time, with "Step n of m" and buttons for the previous and the next step. The first step has no previous button, the last no next button. A single step shows no counter and no buttons (segmenting). | Is exactly one step visible, with its position and only the buttons that lead somewhere? |
| M3  | Choosing a step of a tour or walkthrough highlights the parts it names and dims the others (signaling).                                                                                                                                                                             | During a tour, can you see at once which parts this step is about?                       |
| M4  | A term from the goal's glossary, used in widget text, shows its meaning right next to it when chosen, without leaving the page (pre-training).                                                                                                                                      | Choose a glossary term in a widget: does its meaning appear in place?                    |
| M5  | A task shows a table of contents of its sections with the number of widgets in each and each section's Diátaxis form, and shows one section at a time.                                                                                                                              | Is there a contents list with counts and forms, and only one section on screen?          |
| M6  | A widget shows only what its fields define and actions on it. No decorative images, icons, or ornaments (coherence).                                                                                                                                                                | Does every element in the widget carry data or an action?                                |
| M7  | A diagram that cannot be drawn shows its source text and the error next to it, so the content stays readable.                                                                                                                                                                       | Break a diagram: can you still read its source and the error?                            |

### Typography and hierarchy

- One page title (`h1`), then section headings, then widget titles, then body
  text, then small print. Each level differs in size or weight from the next.
- Small print (labels, ids, counters) is never the only place something
  important is said.
- Line length of running text stays under 80 characters (see D8).
- No decorative element is added anywhere (M6): no illustration, ornament, or
  icon that repeats a word already there without adding meaning.

### Diagrams and data

- Label parts directly; do not make the reader match a legend to colors.
- Encode a category with shape or text as well as color (F6).
- Keep one idea per diagram; split a diagram that needs a paragraph to read.
- Every part a reader can point at can be commented on and explained (M1).
- Show the source when drawing fails (M7). Diagrams may scroll in their own
  frame; the page never does (F5).

## Layer 4: Display settings (Floe)

After the Floe project and IDRC's inclusive design: instead of one version for
everyone, the reader sets how the board looks. The settings apply everywhere
and are kept in the browser.

| Setting      | Values (first is the default) |
| ------------ | ----------------------------- |
| Text size    | 100%, 125%, 150%, 200%        |
| Line spacing | normal, increased             |
| Color theme  | light, dark, high contrast    |
| Motion       | on, reduced                   |
| Density      | airy, compact                 |

| Id  | Rule                                                                                                                                                          | Check question                                                                            |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| L1  | The board offers exactly the settings and values in the table above; no other value can be chosen.                                                            | Does the settings page offer these five settings with these values only?                  |
| L2  | A change applies at once, to this page and every later page, without a reload.                                                                                | Change a setting: does the page change at once, and the next page too?                    |
| L3  | The settings are kept in the browser and apply when the board opens again, before the first paint.                                                            | Reload: are your settings still applied, without a flash of the defaults?                 |
| L4  | At 200% text size and 1280 CSS pixels the page shows all content and actions without horizontal scrolling. Only code and diagrams scroll, in their own frame. | At 200% and 1280px, is the page free of sideways scrolling?                               |
| L5  | On the first visit, a browser that asks for reduced motion or more contrast starts with reduced motion or the high contrast theme.                            | With the browser asking for reduced motion, does a first visit start with motion reduced? |
| L6  | Reset sets every setting back to its default.                                                                                                                 | Does Reset bring every setting back to the first value?                                   |
| L7  | Settings that cannot be read fall back to the defaults, silently.                                                                                             | With broken saved settings, does the board open with defaults and no error?               |
| L8  | At 200% text or compact density, the explanation of a diagram or architecture part stays attached to the part (M1).                                           | At 200% or compact, is each part's explanation still on the part?                         |
| L9  | The display settings are on a how-to page (D2).                                                                                                               | Are the settings on a page labelled How-to, in numbered steps?                            |

### Responsive layout and themes

- Size with relative units (rem, %, ch), never fixed pixels for text, so text
  size scales everything. Fixed widths are capped (a column never needs more
  than its share at 200%).
- Layout works from 320px up; multi-column layouts collapse to one column
  rather than scroll sideways.
- Colors come only from theme tokens (base, primary, secondary, accent, and
  the status colors), so every theme restyles everything. A component never
  hard-codes a color that only works in one theme.
- The high contrast theme is black on white with every color at 7:1 or more,
  and visible borders on every control.
- Review every page you change in each color theme (light, dark, high
  contrast) against the color scheme and motion items of
  `references/checklist.md`, with motion both on and reduced.

## Review

Review every page you changed against `references/checklist.md` before you
deliver. Answer every item with exactly one of:

- **met**: you checked it and it holds;
- **not met**: you checked it and it fails (say where);
- **not checked**: you could not check it (say why).

Never report "met" for an item you did not check. Report the list with the
page name, in your delivery note or on the task.

## UDL

The UDL guidelines from CAST (https://udlguidelines.cast.org/) are reference
vocabulary only, not requirements. Whether a rule is met is decided by its
check question, never by a UDL guideline. When a UDL guideline and a rule give
different answers, the rule applies.
