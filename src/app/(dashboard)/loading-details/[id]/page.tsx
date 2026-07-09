import LoadingDetails from "@/components/loadingDetails/LoadingDetails";

type Props = {
  params: Promise<{
    id: string;
  }>;
};

export default async function LoadingDetailsPage({ params }: Props) {
  const { id } = await params;

  return (
    <main className="space-y-6">
      <LoadingDetails loadingId={id} />
    </main>
  );
}