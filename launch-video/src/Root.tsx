import React from "react";
import {
  AbsoluteFill,
  Composition,
  Easing,
  interpolate,
  spring,
  useCurrentFrame,
} from "remotion";

const C = {
  paper: "#F7F4ED",
  sheet: "#FFFEFB",
  ink: "#17213A",
  cobalt: "#3157D5",
  lift: "#AFC1FF",
  coral: "#EF5B4C",
  line: "#D9DCE4",
  slate: "#636B78",
  yellow: "#E8B44C",
};
const clamp = { extrapolateLeft: "clamp" as const, extrapolateRight: "clamp" as const };
const fade = (f: number, a: number, b: number) => interpolate(f, [a, b], [0, 1], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) });
const rise = (f: number, a: number, b: number, d = 34) => interpolate(f, [a, b], [d, 0], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) });

const baseText: React.CSSProperties = { fontFamily: "Inter, Arial, sans-serif", color: C.ink };

const Eyebrow: React.FC<{ children: React.ReactNode; light?: boolean }> = ({ children, light }) => (
  <div style={{ ...baseText, color: light ? C.lift : C.cobalt, fontSize: 17, fontWeight: 750, letterSpacing: 3.5, textTransform: "uppercase" }}>{children}</div>
);

const SourceSheet: React.FC<{ f: number }> = ({ f }) => (
  <div style={{ width: 255, height: 318, padding: 25, boxSizing: "border-box", background: C.sheet, borderRadius: 18, border: `1px solid ${C.line}`, boxShadow: "0 20px 60px rgba(23,33,58,.10)", opacity: fade(f, 4, 18), translate: `0 ${rise(f, 4, 18, 54)}px`, rotate: "-5deg", position: "relative" }}>
    <div style={{ ...baseText, fontSize: 12, color: C.cobalt, fontWeight: 700, letterSpacing: 1.8 }}>ILLUSTRATIVE DEMO</div>
    <div style={{ height: 1, background: C.line, margin: "20px 0 20px" }} />
    <div style={{ ...baseText, fontSize: 23, lineHeight: 1.2, fontWeight: 750 }}>Lecture notes</div>
    <div style={{ ...baseText, fontSize: 14, color: C.slate, marginTop: 6 }}>Sample course notes</div>
    {[0, 1, 2, 3, 4, 5].map((i) => <div key={i} style={{ height: 7, width: [188, 170, 198, 146, 186, 115][i], background: i === 2 ? "#DDE5FF" : "#E8E8E5", borderRadius: 5, marginTop: i === 2 ? 23 : 13 }} />)}
    <div style={{ position: "absolute", right: 21, bottom: 21, background: "#E7ECFF", color: C.cobalt, font: "700 12px Arial", padding: "8px 11px", borderRadius: 7 }}>SAMPLE</div>
  </div>
);

const ConceptCard: React.FC<{ f: number }> = ({ f }) => (
  <div style={{ width: 250, padding: 23, background: C.sheet, border: `1px solid ${C.line}`, borderRadius: 18, opacity: fade(f, 42, 56), translate: `0 ${rise(f, 42, 56)}px`, boxShadow: "0 20px 60px rgba(23,33,58,.10)" }}>
    <div style={{ ...baseText, fontSize: 12, color: C.cobalt, fontWeight: 750, letterSpacing: 1.7 }}>GROUNDED CONCEPT</div>
    <div style={{ ...baseText, fontSize: 21, fontWeight: 750, marginTop: 16 }}>Key idea</div>
    <div style={{ height: 1, background: C.line, margin: "16px 0" }} />
    <div style={{ ...baseText, color: C.slate, fontSize: 15, lineHeight: 1.5 }}>Mapped from your uploaded notes and linked back to its source.</div>
    <div style={{ marginTop: 18, color: C.cobalt, fontSize: 13, fontWeight: 700 }}>View source passage ↗</div>
  </div>
);

const Phone: React.FC<{ f: number }> = ({ f }) => {
  const enter = spring({ frame: Math.max(0, f - 74), fps: 30, config: { damping: 18, stiffness: 90 } });
  const panelOpacity = fade(f, 88, 100);
  return (
    <div style={{ width: 328, height: 580, borderRadius: 42, background: "#111827", padding: 10, boxSizing: "border-box", boxShadow: "0 35px 90px rgba(15,23,42,.30)", scale: enter, translate: `0 ${interpolate(enter, [0, 1], [100, 0])}px`, opacity: fade(f, 75, 88) }}>
      <div style={{ width: "100%", height: "100%", borderRadius: 33, background: C.paper, overflow: "hidden", position: "relative" }}>
        <div style={{ padding: "29px 23px 0", ...baseText }}>
          <div style={{ display: "flex", alignItems: "center", gap: 9, marginBottom: 24 }}><div style={{ width: 25, height: 25, borderRadius: 7, background: C.cobalt, color: "white", display: "grid", placeItems: "center", fontWeight: 900, fontSize: 15 }}>V</div><b style={{ fontSize: 17 }}>ViaX</b><div style={{ marginLeft: "auto", color: C.cobalt, fontSize: 10, fontWeight: 750, letterSpacing: 1 }}>DEMO PREVIEW</div></div>
          <div style={{ fontSize: 26, letterSpacing: -0.8, fontWeight: 800, lineHeight: 1.12 }}>Build a stronger<br />answer.</div>
          <div style={{ color: C.slate, fontSize: 12, marginTop: 9 }}>Practice from your own material.</div>
          <div style={{ borderRadius: 17, background: C.ink, padding: 17, marginTop: 23, color: "white" }}>
            <div style={{ color: C.lift, fontSize: 10, fontWeight: 750, letterSpacing: 1.2 }}>NEXT BEST ACTION</div>
            <div style={{ fontSize: 16, fontWeight: 700, marginTop: 10 }}>Ready for a viva round?</div>
            <div style={{ color: "#CFD5E1", fontSize: 11, marginTop: 5 }}>Questions grounded in your sources</div>
            <div style={{ background: C.coral, color: C.ink, borderRadius: 9, textAlign: "center", fontWeight: 800, fontSize: 12, padding: 11, marginTop: 14 }}>Start a viva</div>
          </div>
          <div style={{ marginTop: 21, display: "flex", justifyContent: "space-between", alignItems: "center" }}><b style={{ fontSize: 14 }}>Evidence trail</b><span style={{ color: C.cobalt, fontSize: 10, fontWeight: 700 }}>OPEN SOURCE ↗</span></div>
          <div style={{ height: 1, background: C.line, marginTop: 13 }} />
          <div style={{ opacity: panelOpacity }}>
            <div style={{ display: "flex", gap: 10, padding: "14px 0", borderBottom: `1px solid ${C.line}` }}><div style={{ width: 25, height: 25, borderRadius: 7, background: "#E7ECFF", color: C.cobalt, display: "grid", placeItems: "center", fontSize: 12, fontWeight: 800 }}>Q</div><div><b style={{ fontSize: 12 }}>Question</b><div style={{ color: C.slate, fontSize: 10, marginTop: 3 }}>Explain the key idea</div></div></div>
            <div style={{ display: "flex", gap: 10, padding: "14px 0", borderBottom: `1px solid ${C.line}` }}><div style={{ width: 25, height: 25, borderRadius: 7, background: "#FEE2E2", color: C.coral, display: "grid", placeItems: "center", fontSize: 12, fontWeight: 800 }}>✓</div><div><b style={{ fontSize: 12 }}>Cited feedback</b><div style={{ color: C.slate, fontSize: 10, marginTop: 3 }}>See what to strengthen</div></div></div>
            <div style={{ display: "flex", gap: 10, padding: "14px 0" }}><div style={{ width: 25, height: 25, borderRadius: 7, background: "#DCFCE7", color: "#14715B", display: "grid", placeItems: "center", fontSize: 12, fontWeight: 800 }}>↻</div><div><b style={{ fontSize: 12 }}>Next review</b><div style={{ color: C.slate, fontSize: 10, marginTop: 3 }}>Return to the exact passage</div></div></div>
          </div>
        </div>
      </div>
    </div>
  );
};

export const ViaXLaunch: React.FC = () => {
  const f = useCurrentFrame();
  const progress = interpolate(f, [0, 210], [0, 1], { ...clamp, easing: Easing.inOut(Easing.quad) });
  const section1 = f < 42;
  const section3 = f >= 75 && f < 119;
  const outro = f >= 119;
  const titleOpacity = section1 ? 1 : interpolate(f, [32, 46], [1, 0], clamp);
  const promiseOpacity = fade(f, 43, 52) * interpolate(f, [68, 82], [1, 0], clamp);
  const finalOpacity = outro ? fade(f, 123, 145) : 0;

  return (
    <AbsoluteFill style={{ backgroundColor: C.paper, overflow: "hidden" }}>
      <AbsoluteFill style={{ opacity: interpolate(f, [0, 48, 80, 120], [1, 0.24, 0.24, 0], clamp) }}>
        <div style={{ position: "absolute", inset: 0, backgroundImage: `radial-gradient(${C.line} 1px, transparent 1px)`, backgroundSize: "28px 28px", opacity: 0.45 }} />
        <div style={{ position: "absolute", width: 780, height: 780, border: `1px solid ${C.line}`, borderRadius: "50%", right: -240, top: -230 }} />
        <div style={{ position: "absolute", width: 560, height: 560, border: `1px solid ${C.line}`, borderRadius: "50%", right: -130, top: -120 }} />
      </AbsoluteFill>

      {/* Opening */}
      <div style={{ position: "absolute", left: 104, top: 116, opacity: titleOpacity, translate: `0 ${rise(f, 4, 18)}px` }}>
        <Eyebrow>Meet ViaX</Eyebrow>
        <div style={{ ...baseText, fontSize: 78, lineHeight: 1.03, fontWeight: 850, letterSpacing: -4.5, marginTop: 23 }}>Know your<br />material.<br /><span style={{ color: C.cobalt }}>Own your viva.</span></div>
        <div style={{ ...baseText, color: C.slate, fontSize: 23, lineHeight: 1.45, marginTop: 26 }}>Turn your course notes into<br />confident, evidence-led practice.</div>
        <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 35 }}><div style={{ width: 42, height: 3, background: C.coral }} /><span style={{ ...baseText, fontSize: 13, color: C.slate, fontWeight: 700, letterSpacing: 1.6 }}>YOUR MATERIAL. YOUR PROOF.</span></div>
      </div>
      <div style={{ position: "absolute", left: 700, top: 224 }}><SourceSheet f={f} /></div>
      <div style={{ position: "absolute", left: 850, top: 360, opacity: fade(f, 19, 30), translate: `${interpolate(f, [19, 30], [-35, 0], clamp)}px 0` }}>
        <svg width="150" height="100" viewBox="0 0 150 100"><path d="M5 50 C45 5 94 93 143 50" fill="none" stroke={C.cobalt} strokeWidth="3" strokeDasharray="240" strokeDashoffset={interpolate(f, [19, 36], [240, 0], clamp)} /><path d="M132 39 L145 50 L132 61" fill="none" stroke={C.cobalt} strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" /></svg>
      </div>
      <div style={{ position: "absolute", left: 1030, top: 326 }}><ConceptCard f={f} /></div>

      {/* Grounding statement */}
      <div style={{ position: "absolute", left: 95, top: 150, opacity: promiseOpacity, translate: `0 ${rise(f, 43, 56)}px` }}>
        <Eyebrow>From your notes to your next answer</Eyebrow>
        <div style={{ ...baseText, fontSize: 66, lineHeight: 1.12, letterSpacing: -3, fontWeight: 820, marginTop: 29, maxWidth: 1020 }}>Every question starts<br />with <span style={{ color: C.cobalt }}>what you uploaded.</span></div>
        <div style={{ ...baseText, color: C.slate, fontSize: 24, marginTop: 25 }}>Concepts connect to passages you can inspect.</div>
      </div>
      <div style={{ position: "absolute", right: 124, bottom: 132, opacity: promiseOpacity }}><div style={{ background: C.sheet, border: `1px solid ${C.line}`, borderRadius: 14, padding: "17px 21px", ...baseText, fontSize: 14, fontWeight: 650 }}>SOURCE-LINKED BY DESIGN <span style={{ color: C.cobalt, paddingLeft: 8 }}>↗</span></div></div>

      {/* Product reveal */}
      <div style={{ position: "absolute", left: 122, top: 164, opacity: section3 ? fade(f, 79, 91) : 0, translate: `0 ${section3 ? rise(f, 79, 91) : 0}px` }}>
        <Eyebrow>Practice. Reflect. Return.</Eyebrow>
        <div style={{ ...baseText, fontSize: 62, lineHeight: 1.08, letterSpacing: -3.5, fontWeight: 820, marginTop: 26 }}>Better answers,<br />built from evidence.</div>
        <div style={{ ...baseText, color: C.slate, fontSize: 22, lineHeight: 1.5, marginTop: 23 }}>Practise recall. Get cited feedback.<br />Know what to review next.</div>
        <div style={{ display: "flex", gap: 10, marginTop: 35 }}>
          {["RECALL", "CITED FEEDBACK", "REVIEW"].map((word, i) => <div key={word} style={{ opacity: fade(f, 88 + i * 5, 98 + i * 5), padding: "12px 14px", border: `1px solid ${C.line}`, borderRadius: 8, ...baseText, fontSize: 11, fontWeight: 750, letterSpacing: 0.8, color: i === 1 ? C.cobalt : C.ink }}>{word}</div>)}
        </div>
      </div>
      <div style={{ position: "absolute", right: 150, top: 87 }}><Phone f={f} /></div>

      {/* End card */}
      <AbsoluteFill style={{ backgroundColor: C.ink, opacity: finalOpacity }}>
        <div style={{ position: "absolute", width: 820, height: 820, right: -160, top: -370, border: "1px solid rgba(175,193,255,.16)", borderRadius: "50%" }} />
        <div style={{ position: "absolute", width: 620, height: 620, right: -60, top: -270, border: "1px solid rgba(175,193,255,.16)", borderRadius: "50%" }} />
        <div style={{ position: "absolute", left: 0, right: 0, top: 210, textAlign: "center", opacity: finalOpacity, translate: `0 ${rise(f, 128, 150)}px` }}>
          <div style={{ display: "inline-flex", alignItems: "center", gap: 14, color: "white", font: "800 24px Arial", letterSpacing: 0.3 }}><div style={{ width: 39, height: 39, background: C.cobalt, borderRadius: 11, display: "grid", placeItems: "center" }}>V</div>ViaX</div>
          <div style={{ fontFamily: "Arial, sans-serif", fontSize: 81, lineHeight: 1.08, fontWeight: 800, letterSpacing: -4, color: "white", marginTop: 50 }}>Make every answer<br /><span style={{ color: C.lift }}>evidence-led.</span></div>
          <div style={{ color: "#C4CAD4", font: "500 23px Arial", marginTop: 24 }}>Your notes. Your thinking. Your viva.</div>
          <div style={{ display: "inline-block", background: C.coral, color: C.ink, borderRadius: 11, padding: "17px 27px", marginTop: 43, font: "800 17px Arial" }}>MEET VIAX</div>
        </div>
      </AbsoluteFill>

      {/* restrained editorial frame and progress */}
      <div style={{ position: "absolute", left: 56, right: 56, bottom: 42, display: "flex", alignItems: "center", gap: 16, opacity: f < 145 ? 0.78 : 0 }}>
        <div style={{ width: 28, height: 28, background: f >= 119 ? C.lift : C.cobalt, color: f >= 119 ? C.ink : "white", borderRadius: 8, display: "grid", placeItems: "center", font: "800 12px Arial" }}>V</div>
        <span style={{ font: "700 12px Arial", color: f >= 119 ? "white" : C.slate, letterSpacing: 1.5 }}>VIAX</span>
        <div style={{ height: 1, flex: 1, background: f >= 119 ? "rgba(255,255,255,.2)" : C.line, position: "relative" }}><div style={{ position: "absolute", height: 2, top: -0.5, left: 0, width: `${Math.min(100, progress * 100)}%`, background: f >= 119 ? C.coral : C.cobalt }} /></div>
        <span style={{ font: "700 11px Arial", color: f >= 119 ? "#C4CAD4" : C.slate, letterSpacing: 1 }}>YOUR MATERIAL → YOUR VIVA</span>
      </div>
      <div style={{ position: "absolute", left: 65, top: 57, opacity: finalOpacity * 0.7 }}><Eyebrow light>Viva, with evidence.</Eyebrow></div>
    </AbsoluteFill>
  );
};

export const RemotionRoot: React.FC = () => (
  <>
    <Composition id="ViaXLaunch" component={ViaXLaunch} durationInFrames={210} fps={30} width={1920} height={1080} defaultProps={{}} />
  </>
);
