"use client";

import { useEffect, useRef, useState } from "react";

type BaselineResult = { isFinal: boolean; 0?: { transcript?: string } };
type BaselineEvent = { results: ArrayLike<BaselineResult> };
type BaselineRecognition = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onstart: (() => void) | null;
  onaudiostart: (() => void) | null;
  onsoundstart: (() => void) | null;
  onspeechstart: (() => void) | null;
  onresult: ((event: BaselineEvent) => void) | null;
  onerror: ((event: { error: string }) => void) | null;
  onaudioend: (() => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
  abort(): void;
};
type BaselineConstructor = new () => BaselineRecognition;
type BaselineWindow = Window & {
  webkitSpeechRecognition?: BaselineConstructor;
  SpeechRecognition?: BaselineConstructor;
};
type EventRow = { id: number; name: string; detail?: string; time: string };

let nextTestSession = 0;

function errorName(error: unknown) {
  if (typeof error === "object" && error !== null && "name" in error && typeof error.name === "string") return error.name;
  return "unknown";
}

export default function VoiceRecognitionBaseline() {
  const recognitionRef = useRef<BaselineRecognition | null>(null);
  const eventsRef = useRef<EventRow[]>([]);
  const eventCounterRef = useRef(0);
  const sessionRef = useRef("");
  const seenFinalResultsRef = useRef(new Set<number>());
  const finalTextRef = useRef("");
  const [running, setRunning] = useState(false);
  const [events, setEvents] = useState<EventRow[]>([]);
  const [recognizedText, setRecognizedText] = useState("");
  const [interimText, setInterimText] = useState("");
  const [capability, setCapability] = useState("Not started");

  useEffect(() => () => {
    const recognition = recognitionRef.current;
    recognitionRef.current = null;
    if (!recognition) return;
    recognition.onstart = null;
    recognition.onaudiostart = null;
    recognition.onsoundstart = null;
    recognition.onspeechstart = null;
    recognition.onresult = null;
    recognition.onerror = null;
    recognition.onaudioend = null;
    recognition.onend = null;
    try { recognition.abort(); } catch { /* The browser may have already stopped the session. */ }
  }, []);

  const record = (name: string, detail?: string) => {
    const entry = {
      id: ++eventCounterRef.current,
      name,
      ...(detail ? { detail } : {}),
      time: new Date().toLocaleTimeString(),
    };
    eventsRef.current = [...eventsRef.current, entry].slice(-24);
    setEvents(eventsRef.current);
  };

  const start = () => {
    if (recognitionRef.current) return;
    const sessionId = `baseline-${++nextTestSession}`;
    sessionRef.current = sessionId;
    eventsRef.current = [];
    eventCounterRef.current = 0;
    seenFinalResultsRef.current = new Set<number>();
    finalTextRef.current = "";
    setEvents([]);
    setRecognizedText("");
    setInterimText("");

    const browserWindow = window as BaselineWindow;
    const Constructor = browserWindow.webkitSpeechRecognition ?? browserWindow.SpeechRecognition;
    const api = browserWindow.webkitSpeechRecognition
      ? "webkitSpeechRecognition"
      : browserWindow.SpeechRecognition
        ? "SpeechRecognition"
        : "unavailable";
    const webkitApi = browserWindow.webkitSpeechRecognition ? "available" : "unavailable";
    const standardApi = browserWindow.SpeechRecognition ? "available" : "unavailable";
    const secureContext = window.isSecureContext ? "yes" : "no";
    const mediaApi = Boolean(navigator.mediaDevices?.getUserMedia);
    setCapability(`API=${api}; webkit=${webkitApi}; standard=${standardApi}; language=en-US; secureContext=${secureContext}; getUserMediaAPI=${mediaApi ? "available" : "unavailable"}`);
    record("Start clicked", `session=${sessionId}`);
    record("Browser capability", `API=${api}; webkit=${webkitApi}; standard=${standardApi}; language=en-US; secureContext=${secureContext}; getUserMediaAPI=${mediaApi ? "available" : "unavailable"}`);

    if (!Constructor) {
      record("Constructor unavailable");
      return;
    }

    let recognition: BaselineRecognition;
    try {
      recognition = new Constructor();
    } catch (error) {
      const name = errorName(error);
      record("Constructor exception", name);
      return;
    }

    recognition.lang = "en-US";
    recognition.continuous = false;
    recognition.interimResults = true;
    recognitionRef.current = recognition;
    record("Configuration", `session=${sessionId}; language=${recognition.lang}; continuous=false; interimResults=true`);

    recognition.onstart = () => {
      record("onstart", `session=${sessionId}`);
      if (recognitionRef.current === recognition) setRunning(true);
    };
    recognition.onaudiostart = () => record("onaudiostart", `session=${sessionId}`);
    recognition.onsoundstart = () => record("onsoundstart", `session=${sessionId}`);
    recognition.onspeechstart = () => record("onspeechstart", `session=${sessionId}`);
    recognition.onresult = (event) => {
      let finalCount = 0;
      let interimCount = 0;
      const interim: string[] = [];
      for (let index = 0; index < event.results.length; index += 1) {
        const result = event.results[index];
        if (result?.isFinal) {
          finalCount += 1;
          if (seenFinalResultsRef.current.has(index)) continue;
          seenFinalResultsRef.current.add(index);
          const transcript = result[0]?.transcript?.trim();
          if (transcript) finalTextRef.current = [finalTextRef.current, transcript].filter(Boolean).join(" ");
        } else {
          interimCount += 1;
          const transcript = result?.[0]?.transcript?.trim();
          if (transcript) interim.push(transcript);
        }
      }
      record("onresult", `session=${sessionId}; results=${event.results.length}; final=${finalCount}; interim=${interimCount}`);
      setRecognizedText(finalTextRef.current);
      setInterimText(interim.join(" "));
    };
    recognition.onerror = (event) => {
      record("onerror", `session=${sessionId}; code=${event.error}`);
      if (recognitionRef.current === recognition) {
        recognitionRef.current = null;
        setRunning(false);
      }
    };
    recognition.onaudioend = () => record("onaudioend", `session=${sessionId}`);
    recognition.onend = () => {
      record("onend", `session=${sessionId}`);
      if (recognitionRef.current === recognition) {
        recognitionRef.current = null;
        setRunning(false);
      }
    };

    record("start() called", `session=${sessionId}`);
    try {
      recognition.start();
      record("start() returned", `session=${sessionId}`);
      setRunning(true);
    } catch (error) {
      const name = errorName(error);
      record("start() exception", `session=${sessionId}; name=${name}`);
      recognitionRef.current = null;
      setRunning(false);
    }
  };

  const stop = () => {
    const recognition = recognitionRef.current;
    if (!recognition) return;
    record("stop() called", `session=${sessionRef.current}; reason=user clicked Stop`);
    try {
      recognition.stop();
    } catch (error) {
      record("stop() exception", `session=${sessionRef.current}; name=${errorName(error)}`);
      recognitionRef.current = null;
      setRunning(false);
    }
  };

  return <main className="mx-auto w-full max-w-3xl p-6 text-slate-900">
    <h1 className="text-2xl font-bold">Standalone voice recognition test</h1>
    <p className="mt-2 text-sm text-slate-700">
      This page calls the browser speech engine directly. It does not use VoiceTypingField, the shared session manager, or any backend.
    </p>
    <p className="mt-1 text-sm text-slate-700">
      Baseline: prefer <code>webkitSpeechRecognition</code>, use <code>en-US</code>, one-shot recognition, and interim results.
      The shared field now uses the same English configuration, while adding its session manager and bounded startup timeout; Urdu remains configured as <code>ur-PK</code>.
    </p>

    <section className="mt-5 rounded-lg border border-slate-300 bg-white p-4">
      <p className="font-semibold">Capability</p>
      <p className="mt-1 break-words font-mono text-sm">{capability}</p>
      <div className="mt-4 flex gap-2">
        <button type="button" onClick={start} disabled={running} className="rounded bg-blue-700 px-4 py-2 font-semibold text-white disabled:opacity-50">Start</button>
        <button type="button" onClick={stop} disabled={!running} className="rounded border border-slate-400 px-4 py-2 font-semibold disabled:opacity-50">Stop</button>
      </div>
      <div className="mt-4 rounded border border-slate-200 bg-slate-50 p-3">
        <p className="font-semibold">Recognized text (local only)</p>
        <p className="mt-1 min-h-6 whitespace-pre-wrap break-words" aria-live="polite">{recognizedText || "No text yet"}</p>
        {interimText ? <p className="mt-2 border-t border-slate-200 pt-2 text-slate-600"><span className="font-semibold">Interim:</span> {interimText}</p> : null}
      </div>
    </section>

    <section className="mt-5 rounded-lg border border-slate-300 bg-white p-4">
      <h2 className="font-semibold">Lifecycle events · latest 24</h2>
      <p className="mt-1 text-xs text-slate-600">Event rows omit recognized text. Raw browser error codes are shown.</p>
      <ol className="mt-3 max-h-[28rem] space-y-1 overflow-auto font-mono text-xs">
        {events.map((event) => <li key={event.id}>
          <time>{event.time}</time> <strong>{event.name}</strong>{event.detail ? ` — ${event.detail}` : ""}
        </li>)}
      </ol>
    </section>
  </main>;
}
