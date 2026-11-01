import { notFound } from "next/navigation";
import VoiceRecognitionBaseline from "./VoiceRecognitionBaseline";

export default function VoiceRecognitionTestPage() {
  if (process.env.NODE_ENV !== "development") notFound();

  return <VoiceRecognitionBaseline />;
}
