import { ArrowLeftRight, ChartLine, ChartNoAxesColumn, CircleArrowUp, CircleCheck, CirclePlay, Images, List as ListIcon, Plus, Scale } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { TrainingOverview } from "../core/fitlingCore";
import { useCore } from "../core/useCore";
import { supabase } from "../data/supabase";
import { composeWorkout, createProgram, loadTraining, startWorkout, type TrainingRows, typingLanguage } from "../data/training";
import { today } from "../day";
import { useHistoryStack } from "../historyStack";
import { t } from "../i18n";
import { trainingInput } from "../training/input";
import { rememberedMinutes } from "../training/minutes";
import { adviceText, focusTitle, shortDate } from "../training/texts";
import { usesPounds } from "../units";
import { Alert } from "../ui/Alert";
import { List, ListRow, ListSection } from "../ui/List";
import { Body } from "./Body";
import { ComposeWorkout, type ComposeChoice } from "./ComposeWorkout";
import { ExerciseProgress, ExerciseProgressList } from "./ExerciseProgress";
import { NewProgram } from "./NewProgram";
import { Photos } from "./Photos";
import { ProgramDetail } from "./ProgramDetail";
import { Volume } from "./Volume";
import { Workout } from "./Workout";

type Route =
  | { kind: "program"; id: string }
  | { kind: "exercises" }
  | { kind: "exercise"; id: string }
  | { kind: "volume" }
  | { kind: "body" }
  | { kind: "photos" };

/**
 * The training tab (TrainingTabView.swift): carry on with a workout or start the next one, compose one and the coach,
 * the programmes, progress and recent workouts. Apple Health is not on the web. Programmes and progress are pushed
 * screens (back and swiping back go through the browser's history); a workout opens over the whole screen.
 */
export function Training({ userID }: { userID: string }) {
  const core = useCore();
  const [rows, setRows] = useState<TrainingRows>();
  const [failed, setFailed] = useState<string>();
  const [path, setPath] = useState<Route[]>([]);
  const [workout, setWorkout] = useState<string>();
  const [composing, setComposing] = useState<string>();
  const [creating, setCreating] = useState(false);
  const back = useHistoryStack(path.length, (depth) => setPath((shown) => shown.slice(0, depth)));
  const push = (route: Route) => setPath((shown) => [...shown, route]);

  const reload = useCallback(async () => {
    try {
      setRows(await loadTraining(supabase));
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
  }, []);

  useEffect(() => {
    void reload();
    const again = () => document.visibilityState === "visible" && void reload();
    document.addEventListener("visibilitychange", again);
    return () => document.removeEventListener("visibilitychange", again);
  }, [reload]);

  useEffect(() => window.scrollTo(0, 0), [path.length]);

  const input = useMemo(() => (rows ? trainingInput(userID, rows) : undefined), [rows, userID]);
  const overview = useMemo(() => (core && input ? core.trainingOverview({ training: input }) : undefined), [core, input]);
  // One start at a time: a double tap on Start makes one workout, not two.
  const starting = useRef(false);

  async function act(work: () => Promise<void>) {
    try {
      await work();
    } catch (error) {
      setFailed(error instanceof Error ? error.message : "error.server");
    }
    await reload();
  }

  /** A day of a programme, or a free workout; a workout under way opens instead (TrainingViewModel.start). */
  function start(dayID?: string) {
    if (overview?.active) {
      setWorkout(overview.active.id);
      return;
    }
    if (starting.current) return;
    starting.current = true;
    let id: string | undefined;
    // Opened once it is read back, so FitlingCore knows it.
    void act(async () => {
      id = await startWorkout(supabase, userID, dayID, today(), new Date());
    }).then(() => {
      starting.current = false;
      if (id) setWorkout(id);
    });
  }

  /** The composed workout as a day of its own, then started (TrainingViewModel.startComposed). */
  function startComposed(choice: ComposeChoice) {
    setComposing(undefined);
    if (overview?.active) {
      setWorkout(overview.active.id);
      return;
    }
    if (!rows || starting.current) return;
    starting.current = true;
    let id: string | undefined;
    void act(async () => {
      const dayID = await composeWorkout(
        supabase,
        userID,
        rows,
        choice.plan,
        { program: t("training.compose.program"), day: focusTitle(choice.focus), language: typingLanguage() },
        new Date(),
      );
      id = await startWorkout(supabase, userID, dayID, today(), new Date());
    }).then(() => {
      starting.current = false;
      if (id) setWorkout(id);
    });
  }

  const route = path.at(-1);
  let screen;
  if (!core || !input || !overview || !rows) {
    screen = (
      <div className="tab-page" data-page="training">
        <h1 className="large-title">{t("training.title")}</h1>
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
      </div>
    );
  } else if (route?.kind === "program" && !rows.programs.some((program) => program.id === route.id)) {
    // A programme just made on another screen, until it is read back.
    screen = (
      <div className="tab-page pushed" data-page="program">
        <div className="loading tab-loading" aria-busy="true">
          <span className="spinner" role="progressbar" aria-label={t("common.loading")} />
        </div>
      </div>
    );
  } else if (route?.kind === "program") {
    screen = (
      <ProgramDetail
        key={route.id}
        core={core}
        userID={userID}
        input={input}
        rows={rows}
        programID={route.id}
        onBack={back}
        onChanged={reload}
        onStart={start}
        onOpenExercise={(id) => push({ kind: "exercise", id })}
        onOpenCopy={(id) => setPath((shown) => [...shown.slice(0, -1), { kind: "program", id }])}
      />
    );
  } else if (route?.kind === "exercises") {
    screen = <ExerciseProgressList core={core} input={input} equipment={rows.equipment} onBack={back} onOpen={(id) => push({ kind: "exercise", id })} />;
  } else if (route?.kind === "exercise") {
    screen = <ExerciseProgress key={route.id} core={core} userID={userID} input={input} rows={rows} exerciseID={route.id} onBack={back} onChanged={reload} />;
  } else if (route?.kind === "volume") {
    screen = <Volume core={core} input={input} onBack={back} />;
  } else if (route?.kind === "body") {
    screen = <Body core={core} userID={userID} onBack={back} />;
  } else if (route?.kind === "photos") {
    screen = <Photos onBack={back} />;
  } else {
    screen = (
      <TrainingList
        overview={overview}
        minutes={rememberedMinutes(core.trainingChoices())}
        onResume={setWorkout}         onStart={start}
        onCompose={setComposing}
        onCreate={() => setCreating(true)}
        onOpen={push}
      />
    );
  }

  return (
    <>
      {screen}
      {creating && (
        <NewProgram
          onCancel={() => setCreating(false)}
          onCreate={(name, days) => {
            setCreating(false);
            let id: string | undefined;
            // Opened once it is read back, so FitlingCore knows it.
            void act(async () => {
              id = await createProgram(
                supabase,
                userID,
                { name, daysPerWeek: days, dayName: (position) => t("training.day.default %lld", position), language: typingLanguage() },
                new Date(),
              );
            }).then(() => id && push({ kind: "program", id }));
          }}
        />
      )}
      {composing && core && input && rows && (
        <ComposeWorkout
          core={core}
          userID={userID}
          input={input}
          rows={rows}
          focus={composing}
          onCancel={() => setComposing(undefined)}
          onStart={startComposed}
          onChanged={reload}
        />
      )}
      {workout && core && rows && (
        <Workout
          core={core}
          userID={userID}
          rows={rows}
          sessionID={workout}
          onChanged={reload}
          onClose={() => {
            setWorkout(undefined);
            void reload();
          }}
        />
      )}
      {failed && <Alert title={t(failed)} onClose={() => setFailed(undefined)} />}
    </>
  );
}

function SessionLabel({ session, icon }: { session: NonNullable<TrainingOverview["active"]>; icon: "play" | "done" }) {
  return (
    <span className="icon-label">
      {icon === "play" ? <CirclePlay aria-hidden="true" size={22} strokeWidth={2} /> : <CircleCheck aria-hidden="true" size={22} strokeWidth={2} />}
      <span className="row-stack">
        <span className="row-headline">{session.title ?? t("training.session.free")}</span>
        <span className="footnote secondary">{t("training.session.detail %@ %lld", shortDate(session.startedAt), session.setCount)}</span>
      </span>
    </span>
  );
}

function programDetail(program: TrainingOverview["programs"][number]): string {
  if (program.shared) return t("training.program.shared %lld", program.daysPerWeek);
  if (program.composedCount !== undefined) return t("training.program.composed %lld", program.composedCount);
  return t("training.program.own %lld", program.daysPerWeek);
}

function TrainingList({
  overview,
  minutes,
  onResume,
  onStart,
  onCompose,
  onCreate,
  onOpen,
}: {
  overview: TrainingOverview;
  minutes: number;
  onResume: (sessionID: string) => void;
  onStart: (dayID?: string) => void;
  onCompose: (focus: string) => void;
  onCreate: () => void;
  onOpen: (route: Route) => void;
}) {
  const pounds = usesPounds();
  const next = overview.next;
  return (
    <div className="tab-page" data-page="training">
      <h1 className="large-title">{t("training.title")}</h1>
      <List>
        {overview.active ? (
          <ListSection header={t("training.active.title")}>
            <ListRow onClick={() => onResume(overview.active!.id)}>
              <span data-testid="training.resume">
                <SessionLabel session={overview.active} icon="play" />
              </span>
            </ListRow>
          </ListSection>
        ) : (
          next && (
            <ListSection header={t("training.next.title")}>
              <ListRow onClick={() => (next.kind === "programDay" ? onStart(next.dayID) : onCompose(next.focus!))}>
                <span className="row-stack" data-testid="training.next">
                  <span className="row-headline heavy">{next.kind === "programDay" ? next.dayName : focusTitle(next.focus!)}</span>
                  <span className="footnote secondary">
                    {next.kind === "programDay" ? next.programName : t("training.next.compose %lld", minutes)}
                  </span>
                </span>
              </ListRow>
            </ListSection>
          )
        )}
        <ListSection header={t("training.coach.title")} footer={overview.coach.length === 0 ? t("training.coach.empty") : undefined}>
          {!overview.active && (
            <ListRow onClick={() => onCompose("upper_body")}>
              <span className="icon-label" data-testid="training.compose">
                <ListIcon aria-hidden="true" size={22} strokeWidth={2} />
                <span>{t("training.compose.title")}</span>
              </span>
            </ListRow>
          )}
          {overview.coach.map((note) => (
            <div key={note.exerciseID} className="list-row coach-row" data-testid={`training.coach.${note.kind === "heavier" ? "heavier" : "switch"}.${note.exerciseID}`}>
              {note.kind === "heavier" ? <CircleArrowUp aria-hidden="true" size={22} strokeWidth={2} /> : <ArrowLeftRight aria-hidden="true" size={22} strokeWidth={2} />}
              <span className="row-stack">
                <span className="row-headline">{note.name}</span>
                <span className="footnote secondary">
                  {note.kind === "heavier" && note.advice ? adviceText(note.advice, pounds) : t("training.coach.switch %@", note.otherName ?? "")}
                </span>
              </span>
            </div>
          ))}
        </ListSection>
        <ListSection header={t("training.programs.title")}>
          {overview.programs.map((program) => (
            <ListRow key={program.id} onClick={() => onOpen({ kind: "program", id: program.id })} chevron>
              <span className="row-stack" data-testid={`training.program.${program.id}`}>
                <span>{program.name}</span>
                <span className="footnote secondary">{programDetail(program)}</span>
              </span>
            </ListRow>
          ))}
          <ListRow onClick={onCreate}>
            <span className="inline-action" data-testid="training.program.new">
              <Plus aria-hidden="true" size={18} strokeWidth={2.4} />
              <span>{t("training.program.new")}</span>
            </span>
          </ListRow>
        </ListSection>
        <ListSection header={t("training.progress.title")}>
          <ListRow onClick={() => onOpen({ kind: "exercises" })} chevron>
            <span className="icon-label">
              <ChartLine aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("training.progress.exercises")}</span>
            </span>
          </ListRow>
          <ListRow onClick={() => onOpen({ kind: "volume" })} chevron>
            <span className="icon-label">
              <ChartNoAxesColumn aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("training.progress.volume")}</span>
            </span>
          </ListRow>
          <ListRow onClick={() => onOpen({ kind: "body" })} chevron>
            <span className="icon-label">
              <Scale aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("body.title")}</span>
            </span>
          </ListRow>
          <ListRow onClick={() => onOpen({ kind: "photos" })} chevron>
            <span className="icon-label">
              <Images aria-hidden="true" size={22} strokeWidth={2} />
              <span>{t("photos.title")}</span>
            </span>
          </ListRow>
        </ListSection>
        {overview.recent.length > 0 && (
          <ListSection header={t("training.recent.title")}>
            {overview.recent.map((session) => (
              <div key={session.id} className="list-row" data-testid="training.recent">
                <SessionLabel session={session} icon="done" />
              </div>
            ))}
          </ListSection>
        )}
      </List>
    </div>
  );
}
