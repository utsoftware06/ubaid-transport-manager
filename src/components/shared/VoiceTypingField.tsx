"use client";

import {
  cloneElement,
  Children,
  isValidElement,
  useCallback,
  useEffect,
  useLayoutEffect,
  useId,
  useRef,
  useState,
  type FormEvent,
  type ReactElement,
  type ReactNode,
} from "react";
import { Mic, MicOff } from "lucide-react";
import { useLanguage } from "@/contexts/LanguageContext";
import {
  appendRecognizedText,
  normalizeLocalizedDigits,
  validateVoiceCandidate,
  type VoiceFieldMode,
} from "@/components/shared/voiceTypingValidation";

type VoiceInputProps = {
  value?: string | number;
  disabled?: boolean;
  readOnly?: boolean;
  type?: string;
  name?: string;
  id?: string;
  inputMode?: string;
  placeholder?: string;
  "aria-label"?: string;
  className?: string;
  defaultValue?: string | number;
  onChange?: unknown;
  hidden?: boolean;
  "aria-hidden"?: boolean | "true" | "false";
};

type RecognitionResult = { isFinal: boolean; 0: { transcript: string } };
type RecognitionEvent = { results: ArrayLike<RecognitionResult> };
type RecognitionErrorEvent = { error: string };
type RecognitionLike = {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  onstart: (() => void) | null;
  onaudiostart: (() => void) | null;
  onsoundstart: (() => void) | null;
  onspeechstart: (() => void) | null;
  onresult: ((event: RecognitionEvent) => void) | null;
  onerror: ((event: RecognitionErrorEvent) => void) | null;
  onaudioend: (() => void) | null;
  onend: (() => void) | null;
  start(): void;
  stop(): void;
  abort(): void;
};
type RecognitionConstructor = new () => RecognitionLike;
type BrowserWindow = Window & {
  SpeechRecognition?: RecognitionConstructor;
  webkitSpeechRecognition?: RecognitionConstructor;
};

type ActiveVoiceSession = {
  owner: string;
  sessionId: string;
  stop: (reason: string) => void;
  displaced: (reason: string) => void;
};

type VoiceDiagnosticEntry = { sessionId: string; event: string; detail?: string; time: string };
const VOICE_DIAGNOSTICS_ENABLED = process.env.NODE_ENV === "development"
  && process.env.NEXT_PUBLIC_VOICE_DIAGNOSTICS === "true";
let nextVoiceSessionNumber = 0;

const voiceSessionManager = (() => {
  let active: ActiveVoiceSession | null = null;
  return {
    owns(owner: string, sessionId?: string) { return active?.owner === owner && (sessionId === undefined || active.sessionId === sessionId); },
    start(session: ActiveVoiceSession) {
      const previous = active;
      active = session;
      if (previous) {
        const reason = `replaced by ${session.sessionId}`;
        previous.stop(reason);
        previous.displaced(reason);
      }
    },
    stop(owner: string, sessionId: string | null, reason: string, notify = true) {
      if (!sessionId || active?.owner !== owner || active.sessionId !== sessionId) return;
      const previous = active;
      active = null;
      previous.stop(reason);
      if (notify) previous.displaced(reason);
    },
    finish(owner: string, sessionId: string) {
      if (active?.owner === owner && active.sessionId === sessionId) active = null;
    },
  };
})();

function getMessage(language: "en" | "ur", error?: string) {
  if (language === "ur") {
    switch (error) {
      case "unsupported": return "اس براؤزر میں آواز سے لکھنے کی سہولت موجود نہیں۔ دستی طور پر لکھیں۔";
      case "not-allowed":
      case "service-not-allowed": return "مائیکروفون کی اجازت نہیں ملی۔ براؤزر کی اجازتیں دیکھیں یا دستی طور پر لکھیں۔";
      case "audio-capture": return "مائیکروفون دستیاب نہیں۔ مائیکروفون چیک کریں یا دستی طور پر لکھیں۔";
      case "no-speech": return "آواز نہیں ملی۔ دوبارہ کوشش کریں یا دستی طور پر لکھیں۔";
      case "no-result": return "آواز سے متن واپس نہیں آیا۔ دوبارہ کوشش کریں یا دستی طور پر لکھیں۔";
      case "startup-timeout": return "براؤزر نے آواز شناخت شروع نہیں کی۔ دوبارہ کوشش کریں یا دستی طور پر لکھیں۔";
      case "startup-ended": return "براؤزر نے آواز شناخت شروع ہونے سے پہلے ختم کر دی۔ دوبارہ کوشش کریں یا دستی طور پر لکھیں۔";
      case "language-not-supported": return "یہ زبان براؤزر میں دستیاب نہیں۔ آواز کی زبان بدلیں یا دستی طور پر لکھیں۔";
      case "network": return "براؤزر کی تقریر شناخت سروس دستیاب نہیں۔ دستی طور پر لکھیں۔";
      default: return "آواز شناخت نہیں ہو سکی۔ دوبارہ کوشش کریں یا دستی طور پر لکھیں۔";
    }
  }

  switch (error) {
    case "unsupported": return "Voice typing is not supported in this browser. Please type manually.";
    case "not-allowed":
    case "service-not-allowed": return "Microphone permission was denied. Check browser permissions or type manually.";
    case "audio-capture": return "No microphone is available. Check the microphone or type manually.";
    case "no-speech": return "No speech was detected. Try again or type manually.";
    case "no-result": return "Recognition ended without returning text. Try again or type manually.";
    case "startup-timeout": return "The browser did not start speech recognition. Try again or type manually.";
    case "startup-ended": return "The browser ended speech recognition before it started. Try again or type manually.";
    case "language-not-supported": return "This recognition language is unavailable in the browser. Change language or type manually.";
    case "network": return "The browser speech-recognition service is unavailable. Please type manually.";
    default: return "Voice recognition could not continue. Try again or type manually.";
  }
}

function getErrorName(value: unknown) {
  if (typeof value === "object" && value !== null && "name" in value && typeof value.name === "string") return value.name;
  return "unknown";
}

function findInputControl(node: ReactNode): ReactElement<VoiceInputProps> | null {
  if (!isValidElement(node)) return null;
  if (typeof node.type === "string" && (node.type === "input" || node.type === "textarea")) return node as ReactElement<VoiceInputProps>;
  if (typeof node.type === "string") {
    const element = node as ReactElement<{ children?: ReactNode }>;
    for (const child of Children.toArray(element.props.children)) {
      const control = findInputControl(child);
      if (control) return control;
    }
  }
  return null;
}

function isEditableControl(child: ReactElement<VoiceInputProps>, fieldLabel: string, mode: VoiceFieldMode) {
  if (typeof child.type !== "string") return false;
  const semanticText = [fieldLabel, child.props.name, child.props.id, child.props.placeholder, child.props["aria-label"]]
    .filter(Boolean).join(" ").toLowerCase();
  const type = child.props.type ?? "text";
  if (child.props.disabled || child.props.readOnly || child.props.hidden || child.props["aria-hidden"] === true || child.props["aria-hidden"] === "true") return false;
  if (/(^|\s)hidden(\s|$)/i.test(child.props.className ?? "")) return false;
  if (/password|passcode|otp|one.?time.?code|verification.?code|security.?code|secret/i.test(semanticText)) return false;
  if (/calculated|computed|balance after|remaining balance|subtotal|total amount|status/i.test(semanticText)) return false;
  if (child.type === "textarea") return mode === "text";
  if (child.type !== "input" || ["hidden", "file", "password", "checkbox", "radio", "button", "submit", "reset", "image"].includes(type)) return false;

  if (mode === "text") {
    const isTextSearch = type === "search" || /\b(search|find|filter)\b/i.test(fieldLabel);
    if (isTextSearch) return type === "text" || type === "search";
    const structuredHint = /amount|balance|date|time|quantity|weight|rate|price|cost|salary|advance|freight|cnic|ntn|gst|phone|mobile|reference|serial|(^|[^a-z])id([^a-z]|$)|id$/i.test(semanticText);
    return !structuredHint && (type === "text" || type === "search");
  }
  if (mode === "identifier") return type === "text" || type === "tel";
  if (mode === "phone" || mode === "cnic") return type === "text" || type === "tel";
  if (mode === "amount" || mode === "number") return type === "number" || type === "text";
  if (mode === "date") return type === "date" || type === "month" || type === "text";
  if (mode === "email") return type === "email" || type === "text";
  if (mode === "url") return type === "url" || type === "text";
  return false;
}

function getCandidateMessage(language: "en" | "ur", error: string) {
  if (language === "ur") {
    switch (error) {
      case "identifier": return "شناختی نمبر واضح ہندسوں میں نہیں ملا۔ امیدوار دیکھیں یا دستی طور پر لکھیں۔";
      case "number": return "رقم واضح درست عدد نہیں ہے۔ امیدوار دیکھیں یا دستی طور پر لکھیں۔";
      case "date": return "تاریخ واضح YYYY-MM-DD صورت میں نہیں ہے۔ دستی طور پر لکھیں۔";
      case "email": return "ای میل واضح یا درست نہیں۔ دستی طور پر لکھیں۔";
    case "empty": return "کوئی قابلِ اطلاق نتیجہ موجود نہیں۔";
    case "url": return "درست ویب پتہ واضح نہیں۔ دستی طور پر لکھیں۔";
      default: return "نتیجہ واضح نہیں۔ اسے دیکھیں یا دستی طور پر لکھیں۔";
    }
  }
  switch (error) {
    case "identifier": return "No clear digits were recognized. Review the candidate or type it manually.";
    case "number": return "The result is not an unambiguous valid number. Review it or type manually.";
    case "date": return "The result is not an unambiguous YYYY-MM-DD date. Please type it manually.";
    case "email": return "The email candidate is unclear or invalid. Please type it manually.";
    case "empty": return "There is no candidate to apply.";
    case "url": return "The web address is unclear or invalid. Please type it manually.";
    default: return "The candidate is unclear. Review it or type it manually.";
  }
}

type Props = {
  fieldLabel: string;
  value?: string | number;
  onValueChange?: (value: string) => void;
  mode?: VoiceFieldMode;
  contextKey?: string;
  children: ReactElement;
};

/** Opt-in microphone for a single editable text input or textarea. */
export default function VoiceTypingField({ fieldLabel, value, onValueChange, mode = "text", contextKey = "", children }: Props) {
  const { language } = useLanguage();
  const lang = language === "ur" ? "ur" : "en";
  const inputControl = findInputControl(children);
  const owner = useId();
  const wrapperRef = useRef<HTMLDivElement | null>(null);
  const recognitionRef = useRef<RecognitionLike | null>(null);
  const initialControlValue = String(value ?? inputControl?.props.value ?? inputControl?.props.defaultValue ?? "");
  const valueRef = useRef(initialControlValue);
  const lastInputValueRef = useRef(initialControlValue);
  const candidateRef = useRef("");
  const onValueChangeRef = useRef<Props["onValueChange"]>(onValueChange);
  const mountedRef = useRef(false);
  const sessionContextRef = useRef("");
  const activeSessionIdRef = useRef<string | null>(null);
  const activeSessionContextRef = useRef<string | null>(null);
  const startupTimerRef = useRef<{ sessionId: string; handle: number } | null>(null);
  const [listening, setListening] = useState(false);
  const [listeningContext, setListeningContext] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [startingContext, setStartingContext] = useState<string | null>(null);
  const [interim, setInterim] = useState("");
  const [candidate, setCandidate] = useState("");
  const [candidateContext, setCandidateContext] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [errorContext, setErrorContext] = useState<string | null>(null);
  const [recognized, setRecognized] = useState("");
  const [recognizedContext, setRecognizedContext] = useState<string | null>(null);
  const [diagnosticSessionId, setDiagnosticSessionId] = useState<string | null>(null);
  const [diagnosticCapability, setDiagnosticCapability] = useState("");
  const [diagnosticEntries, setDiagnosticEntries] = useState<VoiceDiagnosticEntry[]>([]);
  const rawSessionContext = `${contextKey}\u0000${fieldLabel}\u0000${lang}\u0000${mode}`;
  const [contextEpoch, setContextEpoch] = useState({ raw: rawSessionContext, generation: 0 });
  const sessionGeneration = contextEpoch.raw === rawSessionContext ? contextEpoch.generation : contextEpoch.generation + 1;
  if (contextEpoch.raw !== rawSessionContext) setContextEpoch({ raw: rawSessionContext, generation: sessionGeneration });
  const sessionContext = `${rawSessionContext}\u0000${sessionGeneration}`;
  const isListening = listening && listeningContext === sessionContext;
  const isStarting = starting && startingContext === sessionContext;
  const isSessionActive = isStarting || isListening;
  const showError = Boolean(error) && errorContext === sessionContext;
  const showRecognized = Boolean(recognized) && recognizedContext === sessionContext;
  const showCandidate = mode !== "text" && candidateContext === sessionContext && Boolean(candidate);
  const candidateValidation = mode === "text" ? { value: null, message: "unsupported" } : validateVoiceCandidate(mode, candidate, inputControl?.props.type);
  const hasInputControl = Boolean(inputControl);
  const inputValue = inputControl?.props.value;
  const inputDefaultValue = inputControl?.props.defaultValue;

  const recordDiagnostic = useCallback((sessionId: string, event: string, detail?: string) => {
    if (!VOICE_DIAGNOSTICS_ENABLED || !mountedRef.current) return;
    const entry: VoiceDiagnosticEntry = { sessionId, event, ...(detail ? { detail } : {}), time: new Date().toLocaleTimeString() };
    setDiagnosticEntries((current) => [...current.slice(-13), entry]);
  }, []);

  const clearStartupTimer = useCallback((sessionId: string) => {
    if (startupTimerRef.current?.sessionId !== sessionId) return;
    window.clearTimeout(startupTimerRef.current.handle);
    startupTimerRef.current = null;
    recordDiagnostic(sessionId, "startup timer cleared");
  }, [recordDiagnostic]);

  const stopOwnedSession = useCallback((reason = "session cleanup", expectedSessionId = activeSessionIdRef.current, notify = true) => {
    if (!expectedSessionId) return;
    recordDiagnostic(expectedSessionId, "cleanup requested", reason);
    clearStartupTimer(expectedSessionId);
    voiceSessionManager.stop(owner, expectedSessionId, reason, notify);
    if (activeSessionIdRef.current === expectedSessionId) {
      activeSessionIdRef.current = null;
      activeSessionContextRef.current = null;
      recognitionRef.current = null;
    }
  }, [owner, recordDiagnostic, clearStartupTimer]);

  useLayoutEffect(() => {
    if (value !== undefined) valueRef.current = String(value);
    else if (inputValue !== undefined) valueRef.current = String(inputValue);
    onValueChangeRef.current = onValueChange;
  }, [value, onValueChange, inputValue]);

  useLayoutEffect(() => {
    if (!hasInputControl) return;
    const current = String(value ?? inputValue ?? inputDefaultValue ?? "");
    if ((listening || starting) && current !== lastInputValueRef.current) {
      stopOwnedSession("controlled field value changed");
      candidateRef.current = "";
      setCandidate("");
      setCandidateContext(null);
    }
    valueRef.current = current;
    lastInputValueRef.current = current;
  }, [hasInputControl, value, inputValue, inputDefaultValue, listening, starting, owner, stopOwnedSession]);

  useLayoutEffect(() => {
    sessionContextRef.current = sessionContext;
    return () => {
      const previousSessionId = activeSessionIdRef.current;
      if (previousSessionId && activeSessionContextRef.current === sessionContext) {
        stopOwnedSession("field context changed or component cleanup", previousSessionId, false);
      }
    };
  }, [sessionContext, owner, stopOwnedSession]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      const sessionId = activeSessionIdRef.current;
      if (sessionId) {
        clearStartupTimer(sessionId);
        voiceSessionManager.stop(owner, sessionId, "component unmounted");
        activeSessionIdRef.current = null;
        activeSessionContextRef.current = null;
        recognitionRef.current = null;
      }
    };
  }, [owner, clearStartupTimer]);

  useEffect(() => {
    if (inputControl?.props.disabled || inputControl?.props.readOnly) {
      stopOwnedSession("field became disabled or read-only");
    }
  }, [inputControl?.props.disabled, inputControl?.props.readOnly, stopOwnedSession]);

  const commitValue = (nextValue: string) => {
    const controlledSetter = onValueChangeRef.current;
    if (controlledSetter) {
      valueRef.current = nextValue;
      lastInputValueRef.current = nextValue;
      controlledSetter(nextValue);
      return;
    }

    const control = wrapperRef.current?.querySelector<HTMLInputElement | HTMLTextAreaElement>("input, textarea");
    if (control && inputControl?.props.onChange) {
      const prototype = control instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
      if (setter) setter.call(control, nextValue);
      else control.value = nextValue;
      control.dispatchEvent(new Event("input", { bubbles: true }));
      return;
    }
    if (control) {
      const prototype = control instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
      if (setter) setter.call(control, nextValue);
      else control.value = nextValue;
      control.dispatchEvent(new Event("input", { bubbles: true }));
    }
    valueRef.current = nextValue;
    lastInputValueRef.current = nextValue;
  };

  function finishSession(
    recognition: RecognitionLike,
    session: { hadFinalResult: boolean; hadError: boolean; lastTranscript: string; started: boolean },
    context: string,
    sessionId: string,
  ) {
    if (recognitionRef.current !== recognition || activeSessionIdRef.current !== sessionId || !voiceSessionManager.owns(owner, sessionId)) return;
    clearStartupTimer(sessionId);
    voiceSessionManager.finish(owner, sessionId);
    recognitionRef.current = null;
    activeSessionIdRef.current = null;
    activeSessionContextRef.current = null;
    if (mountedRef.current) {
      setListening(false);
      setListeningContext(null);
      setStarting(false);
      setStartingContext(null);
      setInterim("");
      if (!session.hadFinalResult && !session.hadError) {
        setError(getMessage(lang, session.started ? "no-result" : "startup-ended"));
        setErrorContext(context);
      } else if (session.hadFinalResult) {
        setRecognized(mode === "text" ? session.lastTranscript : (lang === "ur" ? "امیدوار تیار ہے۔ دیکھیں اور لاگو کریں۔" : "Candidate ready. Review it and select Apply."));
        setRecognizedContext(context);
      }
    }
  }

  function startListening() {
    if (!inputControl || inputControl.props.disabled || inputControl.props.readOnly) return;
    setError("");
    setErrorContext(null);
    setRecognized("");
    setRecognizedContext(null);
    setStarting(true);
    setStartingContext(sessionContext);
    setListening(false);
    setListeningContext(null);
    setInterim("");
    candidateRef.current = "";
    setCandidate("");
    setCandidateContext(sessionContext);

    const sessionId = `voice-${++nextVoiceSessionNumber}`;
    setDiagnosticSessionId(sessionId);
    setDiagnosticEntries([]);
    recordDiagnostic(sessionId, "Voice button clicked");

    const browserWindow = window as BrowserWindow;
    const Constructor = browserWindow.webkitSpeechRecognition ?? browserWindow.SpeechRecognition;
    const standardApi = browserWindow.SpeechRecognition ? "available" : "unavailable";
    const webkitApi = browserWindow.webkitSpeechRecognition ? "available" : "unavailable";
    const recognitionApi = browserWindow.webkitSpeechRecognition ? "webkitSpeechRecognition" : browserWindow.SpeechRecognition ? "SpeechRecognition" : "unavailable";
    const configuredLanguage = lang === "ur" ? "ur-PK" : "en-US";
    const mediaApi = typeof navigator !== "undefined" && Boolean(navigator.mediaDevices?.getUserMedia);
    const capability = `API=${recognitionApi}; standard=${standardApi}; webkit=${webkitApi}; language=${configuredLanguage}; secureContext=${window.isSecureContext ? "yes" : "no"}; getUserMediaAPI=${mediaApi ? "available" : "unavailable"}`;
    setDiagnosticCapability(capability);
    recordDiagnostic(sessionId, "browser capability", capability);
    if (!Constructor) {
      recordDiagnostic(sessionId, "constructor unavailable");
      setStarting(false);
      setError(getMessage(lang, "unsupported"));
      setErrorContext(sessionContext);
      return;
    }

    let recognition: RecognitionLike;
    try {
      recognition = new Constructor();
    } catch (errorValue) {
      const errorName = getErrorName(errorValue);
      recordDiagnostic(sessionId, "constructor exception", errorName);
      setStarting(false);
      setError(getMessage(lang, errorName === "NotAllowedError" || errorName === "SecurityError" ? "not-allowed" : errorName));
      setErrorContext(sessionContext);
      return;
    }
    const startedContext = sessionContextRef.current;
    const seenFinalResults = new Set<number>();
    const session = { hadFinalResult: false, hadError: false, lastTranscript: "", started: false };
    recognition.lang = configuredLanguage;
    recognition.continuous = false;
    recognition.interimResults = true;
    recognitionRef.current = recognition;
    activeSessionIdRef.current = sessionId;
    activeSessionContextRef.current = startedContext;
    recordDiagnostic(sessionId, "recognition configured", `language=${recognition.lang}; continuous=${recognition.continuous}; interimResults=${recognition.interimResults}`);

    const pageHideListener = () => {
      if (recognitionRef.current === recognition && activeSessionIdRef.current === sessionId) stopOwnedSession("pagehide", sessionId);
    };
    window.addEventListener("pagehide", pageHideListener, { once: true });

    voiceSessionManager.start({
      owner,
      sessionId,
      stop: (reason) => {
        recordDiagnostic(sessionId, "abort() called", reason);
        clearStartupTimer(sessionId);
        window.removeEventListener("pagehide", pageHideListener);
        try { recognition.abort(); } catch (errorValue) { recordDiagnostic(sessionId, "abort() exception", getErrorName(errorValue)); }
      },
      displaced: (reason) => {
        recordDiagnostic(sessionId, "session displaced", reason);
        if (recognitionRef.current !== recognition || activeSessionIdRef.current !== sessionId) return;
        recognitionRef.current = null;
        activeSessionIdRef.current = null;
        activeSessionContextRef.current = null;
        if (mountedRef.current) {
          setListening(false);
          setListeningContext(null);
          setStarting(false);
          setStartingContext(null);
          setInterim("");
        }
      },
    });

    startupTimerRef.current = {
      sessionId,
      handle: window.setTimeout(() => {
        if (!voiceSessionManager.owns(owner, sessionId) || recognitionRef.current !== recognition || session.started) return;
        session.hadError = true;
        recordDiagnostic(sessionId, "startup timeout", "onstart not received within 10 seconds");
        setError(getMessage(lang, "startup-timeout"));
        setErrorContext(startedContext);
        stopOwnedSession("startup timeout: onstart not received", sessionId);
      }, 10_000),
    };
    recordDiagnostic(sessionId, "startup timer armed", "10 seconds");

    recognition.onstart = () => {
      recordDiagnostic(sessionId, "onstart");
      if (voiceSessionManager.owns(owner, sessionId) && recognitionRef.current === recognition && mountedRef.current) {
        session.started = true;
        clearStartupTimer(sessionId);
        setStarting(false);
        setStartingContext(null);
        setListening(true);
        setListeningContext(startedContext);
      }
    };
    recognition.onaudiostart = () => recordDiagnostic(sessionId, "onaudiostart");
    recognition.onsoundstart = () => recordDiagnostic(sessionId, "onsoundstart");
    recognition.onspeechstart = () => recordDiagnostic(sessionId, "onspeechstart");
    recognition.onresult = (event) => {
      const finalCount = Array.from({ length: event.results.length }, (_, index) => event.results[index]).filter((result) => result?.isFinal).length;
      recordDiagnostic(sessionId, "onresult", `results=${event.results.length}; final=${finalCount}; interim=${event.results.length - finalCount}`);
      if (!voiceSessionManager.owns(owner, sessionId) || recognitionRef.current !== recognition || !mountedRef.current) return;
      if (sessionContextRef.current !== startedContext) {
        stopOwnedSession("result arrived after field context changed", sessionId);
        return;
      }
      setStarting(false);
      setStartingContext(null);
      setListening(true);
      setListeningContext(startedContext);
      const interimParts: string[] = [];
      for (let index = 0; index < event.results.length; index += 1) {
        const result = event.results[index];
        const transcript = result?.[0]?.transcript ?? "";
        if (!result?.isFinal) {
          if (transcript) interimParts.push(transcript);
          continue;
        }
        if (seenFinalResults.has(index)) continue;
        seenFinalResults.add(index);
        if (!transcript.trim()) continue;
        session.hadFinalResult = true;
        session.lastTranscript = appendRecognizedText(session.lastTranscript, transcript);
        setRecognized(session.lastTranscript);
        setRecognizedContext(startedContext);
        if (mode === "text") {
          const nextValue = appendRecognizedText(valueRef.current, transcript);
          if (nextValue !== valueRef.current) commitValue(nextValue);
        } else {
          candidateRef.current = appendRecognizedText(candidateRef.current, transcript);
          setCandidate(candidateRef.current);
          setCandidateContext(startedContext);
        }
      }
      setInterim(interimParts.join(" "));
    };
    recognition.onerror = (event) => {
      recordDiagnostic(sessionId, "onerror", `code=${event.error}`);
      if (!voiceSessionManager.owns(owner, sessionId) || recognitionRef.current !== recognition || !mountedRef.current) return;
      session.hadError = true;
      setError(getMessage(lang, event.error));
      setErrorContext(startedContext);
      window.removeEventListener("pagehide", pageHideListener);
      finishSession(recognition, session, startedContext, sessionId);
    };
    recognition.onaudioend = () => recordDiagnostic(sessionId, "onaudioend");
    recognition.onend = () => {
      recordDiagnostic(sessionId, "onend");
      window.removeEventListener("pagehide", pageHideListener);
      finishSession(recognition, session, startedContext, sessionId);
    };

    recordDiagnostic(sessionId, "start() called");
    try {
      recognition.start();
      recordDiagnostic(sessionId, "start() returned");
    } catch (errorValue) {
      const errorName = getErrorName(errorValue);
      recordDiagnostic(sessionId, "start() exception", errorName);
      clearStartupTimer(sessionId);
      window.removeEventListener("pagehide", pageHideListener);
      voiceSessionManager.finish(owner, sessionId);
      if (activeSessionIdRef.current === sessionId) {
        activeSessionIdRef.current = null;
        activeSessionContextRef.current = null;
        recognitionRef.current = null;
      }
      setListening(false);
      setListeningContext(null);
      setStarting(false);
      setStartingContext(null);
      const errorCode = errorName === "NotAllowedError" || errorName === "SecurityError" ? "not-allowed" : errorName;
      setError(getMessage(lang, errorCode));
      setErrorContext(startedContext);
    }
  }

  function stopListening() {
    const sessionId = activeSessionIdRef.current;
    const recognition = recognitionRef.current;
    if (!sessionId || !recognition || !voiceSessionManager.owns(owner, sessionId)) return;
    recordDiagnostic(sessionId, "stop() called", "user pressed Stop");
    try {
      recognition.stop();
    } catch (errorValue) {
      const errorName = getErrorName(errorValue);
      recordDiagnostic(sessionId, "stop() exception", errorName);
      setError(getMessage(lang, errorName));
      setErrorContext(sessionContext);
      stopOwnedSession("stop() threw", sessionId);
    }
  }

  function applyCandidate() {
    if (!showCandidate || isListening || !candidateValidation.value || disabled) return;
    commitValue(candidateValidation.value);
    candidateRef.current = "";
    setCandidate("");
    setCandidateContext(null);
  }

  if (!inputControl || !isEditableControl(inputControl, fieldLabel, mode)) return children;
  const directControl = typeof children.type === "string" && (children.type === "input" || children.type === "textarea");
  const spanClasses = directControl ? inputControl.props.className?.match(/(?:^|\s)(?:[a-z]+:)?col-span-\S+/g)?.join(" ").trim() ?? "" : "";
  const className = inputControl.props.className?.replace(/(?:^|\s)(?:[a-z]+:)?col-span-\S+/g, " ").trim();
  const voiceInput = directControl ? cloneElement(inputControl, { className }) : children;
  const disabled = Boolean(inputControl.props.disabled || inputControl.props.readOnly);
  const disclaimer = lang === "ur"
    ? "رومن اردو کی خودکار تبدیلی کی ضمانت نہیں۔"
    : "Roman Urdu transcription is not guaranteed.";
  const disclaimerId = `${owner}-voice-help`;
  const actionLabel = isSessionActive
    ? (lang === "ur" ? "سننا بند کریں" : "Stop listening")
    : (lang === "ur" ? "آواز سے لکھیں" : "Voice typing");
  const feedback = showError
    ? error
    : isStarting
      ? (lang === "ur" ? `${fieldLabel} کے لیے آواز کی شناخت شروع ہو رہی ہے…` : `Starting voice recognition for ${fieldLabel}…`)
      : isListening
        ? `${lang === "ur" ? `سن رہے ہیں: ${fieldLabel}` : `Listening: ${fieldLabel}`}${interim ? ` — ${interim}` : ""}`
        : showRecognized
          ? (mode === "text"
            ? `${lang === "ur" ? "پہچانا گیا:" : "Recognized:"} ${recognized}`
            : recognized)
          : "";
  const updateFromInput = (event: FormEvent<HTMLDivElement>) => {
    const target = event.target;
    if (target instanceof HTMLInputElement || target instanceof HTMLTextAreaElement) {
      valueRef.current = target.value;
      lastInputValueRef.current = target.value;
      if (mode !== "text") {
        candidateRef.current = "";
        setCandidate("");
        setCandidateContext(null);
      }
    }
  };

  return <div ref={wrapperRef} onInputCapture={updateFromInput} className={`grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-stretch gap-2 ${spanClasses}`}>
    {voiceInput}
    {isSessionActive ? (
      <button type="button" onMouseDown={(event) => event.preventDefault()} onClick={stopListening} className="inline-flex items-center gap-1 self-start rounded-lg border border-rose-300 bg-rose-50 px-2 py-2 text-xs font-bold text-rose-800" aria-label={`${actionLabel}: ${fieldLabel}`} aria-describedby={disclaimerId} title={disclaimer}>
        <MicOff size={15} aria-hidden="true" />{lang === "ur" ? "روکیں" : "Stop"}
      </button>
    ) : (
      <button type="button" disabled={disabled} onMouseDown={(event) => event.preventDefault()} onClick={startListening} className="inline-flex items-center gap-1 self-start rounded-lg border border-slate-300 bg-white px-2 py-2 text-xs font-bold text-slate-700 hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-50" aria-label={`${actionLabel}: ${fieldLabel}`} aria-describedby={disclaimerId} title={disclaimer}>
        <Mic size={15} aria-hidden="true" />{lang === "ur" ? "آواز" : "Voice"}
      </button>
    )}
    <span id={disclaimerId} className="sr-only">{disclaimer}</span>
    {showCandidate && <div className="col-span-2 rounded-md border border-amber-200 bg-amber-50 p-2 text-xs text-slate-800">
      <p className="font-semibold">{lang === "ur" ? "پہچانا گیا امیدوار:" : "Recognized candidate:"} <span dir="auto">{candidateValidation.value ?? normalizeLocalizedDigits(candidate)}</span></p>
      {candidateValidation.value ? <button type="button" disabled={isListening || disabled} onMouseDown={(event) => event.preventDefault()} onClick={applyCandidate} className="mt-2 rounded border border-emerald-300 bg-white px-2 py-1 font-bold text-emerald-800 disabled:opacity-50">{lang === "ur" ? "لاگو کریں" : "Apply"}</button> : <p role="status" className="mt-1 font-medium text-amber-900">{getCandidateMessage(lang, candidateValidation.message)}</p>}
    </div>}
    {feedback ? <span role="status" aria-live="polite" className={`col-span-2 text-xs font-medium ${showError ? "text-rose-700" : "text-slate-600"}`}>{feedback}</span> : null}
    {VOICE_DIAGNOSTICS_ENABLED && diagnosticSessionId && <section className="col-span-2 rounded border border-amber-300 bg-amber-50 p-2 text-[11px] leading-4 text-slate-800" aria-label="Development voice diagnostics">
      <p className="font-bold">Voice diagnostics · {diagnosticSessionId}</p>
      <p className="break-words">{diagnosticCapability}</p>
      <ol className="mt-1 max-h-40 list-inside list-decimal overflow-auto font-mono">
        {diagnosticEntries.map((entry, index) => <li key={`${entry.sessionId}-${index}`}>
          <time>{entry.time}</time> <span>[{entry.sessionId}]</span> <strong>{entry.event}</strong>{entry.detail ? ` — ${entry.detail}` : ""}
        </li>)}
      </ol>
      <p className="mt-1 text-slate-600">Transcript and field contents are not recorded here.</p>
    </section>}
  </div>;
}
