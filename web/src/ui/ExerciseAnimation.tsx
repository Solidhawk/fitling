import { Pause, Play } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { t } from "../i18n";

// A moving example of an exercise (ExerciseAnimationView on iOS): a sheet of rendered frames and the order to show
// them in, from design/oefeningen/3d via public/exercises. A tap pauses it; with "reduce motion" the start and the
// end of the movement stand still next to each other.

interface Manifest {
  fps: number;
  frames: number;
  columns: number;
  animations: Record<string, number[]>;
}

let manifest: Promise<Manifest | undefined> | undefined;

function loadManifest(): Promise<Manifest | undefined> {
  manifest ??= fetch(`${import.meta.env.BASE_URL}exercises/ExerciseAnimations.json`)
    .then((response) => (response.ok ? (response.json() as Promise<Manifest>) : undefined))
    .catch(() => {
      manifest = undefined;
      return undefined;
    });
  return manifest;
}

/** Whether an exercise has an animation, for the screens that only show its section then. */
export function useAnimation(exerciseID: string): Manifest | undefined {
  const [found, setFound] = useState<Manifest>();
  useEffect(() => {
    let current = true;
    void loadManifest().then((loaded) => current && setFound(loaded && loaded.animations[exerciseID]?.length ? loaded : undefined));
    return () => {
      current = false;
    };
  }, [exerciseID]);
  return found;
}

function reducesMotion(): boolean {
  return typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
}

function Frame({ exerciseID, manifest, index, label }: { exerciseID: string; manifest: Manifest; index: number; label?: string }) {
  const rows = Math.ceil(manifest.frames / manifest.columns);
  const column = index % manifest.columns;
  const row = Math.floor(index / manifest.columns);
  return (
    <span
      className="exercise-frame"
      role={label ? "img" : undefined}
      aria-label={label}
      style={{
        backgroundImage: `url(${import.meta.env.BASE_URL}exercises/${exerciseID}.webp)`,
        backgroundSize: `${manifest.columns * 100}% ${rows * 100}%`,
        backgroundPosition: `${manifest.columns > 1 ? (column / (manifest.columns - 1)) * 100 : 0}% ${rows > 1 ? (row / (rows - 1)) * 100 : 0}%`,
      }}
    />
  );
}

export function ExerciseAnimation({ exerciseID, manifest }: { exerciseID: string; manifest: Manifest }) {
  const sequence = manifest.animations[exerciseID];
  const [still] = useState(reducesMotion);
  const [paused, setPaused] = useState(false);
  const [step, setStep] = useState(0);
  const started = useRef(performance.now());
  const pausedAt = useRef<number>();

  useEffect(() => {
    if (still || paused) return;
    let frame = requestAnimationFrame(function tick(now) {
      setStep(Math.floor(((now - started.current) / 1000) * manifest.fps) % sequence.length);
      frame = requestAnimationFrame(tick);
    });
    return () => cancelAnimationFrame(frame);
  }, [still, paused, manifest.fps, sequence.length]);

  function toggle() {
    const now = performance.now();
    if (pausedAt.current !== undefined) {
      started.current += now - pausedAt.current;
      pausedAt.current = undefined;
      setPaused(false);
    } else {
      pausedAt.current = now;
      setPaused(true);
    }
  }

  if (still) {
    return (
      <span className="exercise-stills" role="img" aria-label={t("training.animation.still")} data-testid="exercise.animation.still">
        <Frame exerciseID={exerciseID} manifest={manifest} index={0} />
        <Frame exerciseID={exerciseID} manifest={manifest} index={manifest.frames - 1} />
      </span>
    );
  }
  return (
    <button
      type="button"
      className="exercise-animation"
      aria-label={t(paused ? "training.animation.play" : "training.animation.pause")}
      data-testid="exercise.animation"
      onClick={toggle}
    >
      <Frame exerciseID={exerciseID} manifest={manifest} index={sequence[step]} />
      <span className="exercise-animation-state" aria-hidden="true">
        {paused ? <Play size={13} fill="currentColor" strokeWidth={0} /> : <Pause size={13} fill="currentColor" strokeWidth={0} />}
      </span>
    </button>
  );
}
