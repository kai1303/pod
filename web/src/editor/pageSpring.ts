import { cubicBezier, easeOut, spring } from "motion";

export const pageSpring = {type: "spring", visualDuration: 0.32, bounce: 0.32} as const;

// AppKit runs this same Motion curve on its display link without crossing the bridge per frame.
export function nativePanSpring() {
  const curve = spring({...pageSpring, keyframes: [0, 1]});
  const samples: number[] = [];
  for (let frame = 0; ; frame++) {
    const {value, done} = curve.next(frame * 1000 / 60);
    samples.push(value);
    if (done) return samples;
  }
}

// Sample Motion's page-turn easing once for the native canvas compositor.
export const pageTurnEase = [0.2, 0.8, 0.2, 1] as const;
const pageTurnCurve = cubicBezier(...pageTurnEase);
export const pageTurnSamples = Array.from({length: 13}, (_, frame) => pageTurnCurve(frame / 12));

export const deleteEaseSamples = Array.from({length: 13}, (_, frame) => easeOut(frame / 12));
