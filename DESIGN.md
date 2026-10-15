---
name: ViaX
description: A warm-paper evidence docket for building defensible viva answers from a student's own material.
colors:
  evidence-cobalt: "#3157D5"
  deep-ink: "#17213A"
  evidence-lift: "#AFC1FF"
  proof-coral: "#EF5B4C"
  review-yellow: "#E8B44C"
  danger: "#BC3D37"
  warning: "#8A5B00"
  good: "#14715B"
  danger-lift: "#FF9C92"
  warning-lift: "#F4CD68"
  good-lift: "#71D6B7"
  light-ink: "#171A21"
  light-slate: "#636B78"
  light-line: "#D9DCE4"
  light-canvas: "#F7F4ED"
  light-card: "#FFFEFB"
  dark-ink: "#F3F5F8"
  dark-slate: "#AEB5C2"
  dark-line: "#303746"
  dark-canvas: "#0E1118"
  dark-card: "#171B24"
  white: "#FFFFFF"
  cobalt-wash-light: "#E7ECFF"
  danger-wash-light: "#FEE2E2"
  warning-wash-light: "#FEF3C7"
  good-wash-light: "#DCFCE7"
typography:
  hero:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "52px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-2px"
  display:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "28px"
    fontWeight: 800
    lineHeight: 1.08
    letterSpacing: "-0.7px"
  title:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "21px"
    fontWeight: 700
    lineHeight: 1.25
    letterSpacing: "-0.3px"
  heading:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.3
  body:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "15.5px"
    fontWeight: 500
    lineHeight: 1.45
  body-quiet:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.45
  label:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "12.5px"
    fontWeight: 600
    lineHeight: 1.35
  stat:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "26px"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.8px"
    fontFeature: "tnum"
rounded:
  progress: "4px"
  compact: "8px"
  small: "10px"
  feedback: "12px"
  control: "14px"
  row: "16px"
  card: "18px"
  panel: "22px"
  study-card: "24px"
  pill: "999px"
spacing:
  micro: "4px"
  xs: "6px"
  sm: "8px"
  compact: "10px"
  md: "12px"
  control: "14px"
  lg: "16px"
  section: "18px"
  gutter: "20px"
  panel: "22px"
  screen: "24px"
  large: "28px"
  xl: "32px"
  bottom: "40px"
components:
  button-primary-light:
    backgroundColor: "{colors.evidence-cobalt}"
    textColor: "{colors.white}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "16px 20px"
    height: "56px"
  button-primary-dark:
    backgroundColor: "{colors.evidence-lift}"
    textColor: "{colors.deep-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "16px 20px"
    height: "56px"
  button-proof:
    backgroundColor: "{colors.proof-coral}"
    textColor: "{colors.deep-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "16px 20px"
    height: "56px"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.evidence-cobalt}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "14px 20px"
    height: "52px"
  input-light:
    backgroundColor: "{colors.light-card}"
    textColor: "{colors.light-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "16px"
  input-dark:
    backgroundColor: "{colors.dark-card}"
    textColor: "{colors.dark-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "16px"
  card-light:
    backgroundColor: "{colors.light-card}"
    textColor: "{colors.light-ink}"
    rounded: "{rounded.card}"
    padding: "16px"
  card-dark:
    backgroundColor: "{colors.dark-card}"
    textColor: "{colors.dark-ink}"
    rounded: "{rounded.card}"
    padding: "16px"
---

# Design System: ViaX

## Overview

**Creative North Star: "The Evidence Docket"**

ViaX is an evidence docket for active recall: every study action begins in the student's material and resolves into a defensible viva answer. Warm paper is the working ground, deep ink gives the interface academic gravity, evidence cobalt identifies grounded action, and coral marks the moment a student commits to proof. The result should feel like a precise personal record under active examination, not a generic chatbot, learning dashboard, or gamified card stack.

Material 3 supplies the behavior: familiar controls, navigation, system Back, focus and press states, sheets, snackbars, safe areas, and adaptive width. ViaX supplies the form: one decisive readiness or next-action field, compact ruled records, explicit evidence status, and a code-led Study hub that turns the student's real concepts into a personalized round.

**Key Characteristics:**

- Warm paper canvas with near-white working sheets and deep neutral ink.
- Evidence cobalt for grounded selection, focus, and primary action.
- A single coral proof mark for the decisive action inside an ink field.
- Dense, compact records in place of stacked dashboard cards.
- Visible source, mastery, due-state, processing, and citation language.
- Exact Material 3 interaction behavior across phone and expanded widths.

## Colors

The palette reads as ink and annotation on paper. Cobalt is evidence, coral is commitment, and semantic colors remain sparse enough to retain meaning.

### Primary

- **Evidence Cobalt:** The main filled action, focused border, selected control, active icon, progress accent, and evidence-bearing link.
- **Deep Ink:** The dominant readiness or Study field, strong brand field, and high-authority foreground.
- **Evidence Lift:** The dark-theme primary and focus color; it restores contrast without changing cobalt's semantic role.

### Secondary

- **Proof Coral:** The one decisive “start/review/submit” action when it sits inside a deep-ink field. It is a proof mark, not a general accent.
- **Review Yellow:** Starred or due-review emphasis in small, named controls and records.

### Tertiary

- **Good / Warning / Danger:** Mastery, readiness, recoverable risk, failure, and destructive meaning. Light and dark lift variants preserve legibility.

### Neutral

- **Light Canvas / Light Card:** Warm paper behind an almost-white working sheet.
- **Light Ink / Light Slate / Light Line:** Main copy, secondary metadata, and fine ruled structure.
- **Dark Canvas / Dark Card:** Blue-black page and raised working sheet; dark mode is composed, not inverted.
- **Dark Ink / Dark Slate / Dark Line:** Main copy, metadata, and rules in dark mode.

Light mode uses cobalt with white for primary actions. Dark mode uses evidence lift with deep ink, while status surfaces become low-opacity semantic washes. Every readiness or mastery color is paired with a word, value, icon, or pattern.

**The Evidence Rule.** Cobalt marks an action or state grounded in the student's material; do not use it as undifferentiated decoration.

**The Proof-Mark Rule.** Coral appears at the commitment point inside a decisive field. If several coral actions compete on one screen, the hierarchy is broken.

**The Status-in-Words Rule.** Color never carries readiness, mastery, failure, or due-state alone.

## Typography

**Display Font:** Roboto, with the Android system face as fallback  
**Body Font:** Roboto, with the Android system face as fallback  
**Label/Stat Font:** The same platform face; changing values use tabular figures.

**Character:** Neutral, compact, and editorial. Weight and tight tracking make the next question or score decisive; body and metadata remain calm enough for dense evidence records.

### Hierarchy

- **Hero** (800, 52 sp, 1.0, -2 sp): Exceptional readiness numerals; a signature score may optically rise to 64 sp.
- **Display** (800, 28 sp, 1.08, -0.7 sp): Screen titles and first-view statements.
- **Title** (700, 21 sp, 1.25, -0.3 sp): Decisive field headings, questions, sheets, and major sections.
- **Heading** (700, 17 sp, 1.3): Section labels and compact component headings.
- **Body** (500, 15.5 sp, 1.45): Main task and explanation copy.
- **Body Quiet** (500, 14 sp, 1.45): Supporting evidence, timing, and metadata.
- **Label** (600, 12.5 sp, 1.35): Status, mastery, counts, captions, and navigation.
- **Stat** (800, 26 sp, 1.0, -0.8 sp, tabular): Scores, timers, counts, and changing values.

**The Answer-First Rule.** The question, answer, score, or next action wins through type role and spacing; decoration never competes with it.

## Layout

### Information architecture

The primary shell has five task destinations: **Home**, **Library**, **Study**, **Viva**, and **Progress**. Profile and settings stay behind the Home avatar. Each destination retains its own navigation stack; selecting the active destination returns to its root, and system Back unwinds local history before returning to Home.

The product story is linear even when navigation is not: **upload → grounded concepts → build a personalized round → recall → cited evaluation → due review**. Library owns subjects, documents, processing, concepts, and source inspection. Study owns repeatable active-recall modes and round construction. Viva owns oral examination and cited evaluation. Progress owns due queues, history, and trends. Home compresses current readiness and the next real action.

### Spatial model

Use a centered single working column, not a dashboard grid. Phone screens use a 20 dp gutter; authentication and empty states may use 24 dp. The Home core is constrained near 560 dp, Study near 680 dp, and reading/graph surfaces near 620 dp. Keep 40 dp below long lists and respect system/keyboard insets.

The first viewport contains one decisive readiness or next-action field followed by compact subject or study records. Repeated entities are 42–48 dp-leading rows with a fine bottom rule, not individually floating cards. Horizontal rails are allowed for the four Study activities—Cards, Learn, Test, Match—because they are peer choices, not the reading order.

At widths below 800 dp, the five destinations use the 68 dp Material navigation bar. At 800 dp and above they move to a navigation rail; at 1100 dp and above the rail extends. The same destinations, state, and navigation semantics survive the transition.

**The One Docket Rule.** Each viewport has one dominant field or record set. Supporting information follows in compact rows rather than nested panels.

**The Dense Record Rule.** Subjects, documents, concepts, citations, and due items expose identity, status, and one useful action in a single scan line whenever content permits.

## Elevation & Depth

The system is flat by default. Canvas/card tone, a 1 dp line, and the contrast of a deep-ink field establish depth. App bars have zero elevation and no surface tint. Tonal Material layers may appear for sheets and menus; arbitrary ambient shadows do not.

The only authored shadow is the active flipping study card (`0 8px 16px rgba(0,0,0,0.04)`), where physical depth explains the interaction.

**The Evidence-on-Paper Rule.** Resting records are separated by tone and rules; shadow is reserved for a component whose movement makes depth meaningful.

## Shapes

Corners are technical and measured: progress tracks use 4 dp; compact badges 8–10 dp; feedback and mastery cells 12 dp; controls and mode tiles 14 dp; rows 16 dp; ordinary cards 18 dp; decisive readiness/Study fields 22 dp; the physical flashcard 24 dp. Full pills are limited to short statuses, counts, and dates. Circular geometry is limited to avatars, small state dots, and native icon controls.

Borders are normally 1 dp in the current line color; focused fields rise to 1.5 dp in the active primary. Do not wrap a ruled row in another rounded container.

## Components

### Buttons

- **Primary:** Full-width cobalt with white text in light mode; evidence lift with deep ink in dark mode. Standard height is 56 dp with a 14 dp radius and 16 sp bold label.
- **Proof action:** Coral with deep ink, used inside the deep-ink readiness or Study field for the single action that starts, reviews, or submits evidence.
- **Outlined:** Transparent, 52 dp high, with a 1.5 dp current-theme line and theme primary label.
- **Behavior:** Use Material state layers, InkSparkle, semantics, and a minimum 48×48 dp target. Destructive labels state the irreversible action.

### Chips

- **Style:** Short, word-led status, date, count, scope, or mastery labels; 8–10 dp horizontal and 3–5 dp vertical padding.
- **State:** Semantic wash plus text/icon. Filter and segmented choices use Material selection behavior rather than custom gesture handling.

### Cards / Containers

- **Ordinary surfaces:** Current card tone, 16–18 dp corners, 1 dp line, 14–18 dp internal padding, no shadow.
- **Decisive field:** Deep ink, 22 dp corners and 22 dp padding; contains one heading, grounded context, and one proof action.
- **Rows:** Prefer a bottom rule and 12–14 dp vertical padding to a separate card for every record.

### Inputs / Fields

- **Style:** Filled current card tone, 14 dp radius, 16 dp padding, and a current line at rest.
- **Focus:** 1.5 dp cobalt in light mode or evidence lift in dark mode; cursor, selection, and handles follow the active theme primary.
- **Error / Disabled:** Pair semantic wash, icon, and specific recovery text. Voice may augment an answer field, but typing always remains available.

### Navigation

The five destinations use familiar Material icons and 12 sp labels. Phone navigation is 68 dp high with a cobalt-tinted selected indicator; expanded layouts use the corresponding rail. Per-tab history and Android Back behavior are part of the component contract.

### Study Hub

The Study hub is the signature surface. A subject selector establishes evidence scope. A 22 dp deep-ink field names what is due or how to build momentum, gives an honest time/goal line, and contains one coral action. Cards, Learn, Test, and Match appear as compact 108×76 dp outlined mode tiles. Search and concept records follow; each concept row combines a 42 dp mastery cell, concept name, named mastery state, and a star action.

“Build a study round” is a Material bottom sheet. It configures activity, material scope (smart, due, weak, starred, or all), round length, and shuffle before starting. A filter must contain at least two grounded concepts; otherwise the UI explains the blocker instead of fabricating a round.

### Evidence and Evaluation Records

Document processing, grounded concepts, viva questions, answer gaps, citations, disputes, and due-review items remain inspectable. Failures show the stored reason and a recovery path. Evaluation links back to source passages; plausible prose is never presented as evidence.

### Interaction principles

- Lead with the next useful action, then let the student inspect why it is valid.
- Preserve context across destinations and refresh dependent readiness/mastery state after mutation.
- Use bottom sheets for bounded configuration, snackbars for transient recoverable feedback, and dialogs only for interrupting decisions.
- Prefer explicit loading/progress language and real empty states to skeleton content that looks like student data.
- Material motion is short and directional: compact state changes around 220 ms, cards around 300 ms, entrance transitions around 400 ms, and score/progress reveals up to 800 ms.
- When `MediaQuery.disableAnimationsOf(context)` is true, critical transforms, flips, and reveals resolve immediately; information and task completion do not depend on animation.

## Do's and Don'ts

### Do:

- **Do** spell the canonical name **ViaX** and keep all visible study data tied to the signed-in student.
- **Do** make the chain from uploaded source to concept, practice, evaluation, citation, and review visible.
- **Do** keep the first viewport decisive: one readiness or next-action field, then compact records.
- **Do** use Material 3 controls, state layers, safe areas, predictive/system Back, sheets, snackbars, navigation bar/rail, and padded touch targets exactly as Android users expect.
- **Do** preserve at least 48×48 dp targets, text scaling, light/dark themes, reduced motion, and a typing path wherever voice is offered.
- **Do** pair color with words, icons, values, or patterns and write specific recovery copy for failure or insufficient grounded material.

### Don't:

- **Don't** invent subjects, concepts, citations, mastery, readiness, or plausible sample evidence.
- **Don't** turn the product into a stacked dashboard, masonry card wall, chat transcript, or gamified flashcard clone.
- **Don't** use gradients, glass, neon, purple AI styling, discipline-specific imagery, generic sparkles, or decorative charts.
- **Don't** spread coral across the screen or use cobalt as atmosphere; preserve their evidence and proof roles.
- **Don't** hide processing/provider failures, disable typing in favor of voice, or make color or motion the only carrier of meaning.
- **Don't** replace Material navigation, native controls, per-tab history, or Android Back with custom behavior.
