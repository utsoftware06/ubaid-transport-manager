import OtherAddaAccount from "@/components/other-addas/OtherAddaAccount";

export default async function OtherAddaAccountPage({ searchParams }: {
  searchParams: Promise<{ otherAddaId?: string | string[] }>;
}) {
  const { otherAddaId } = await searchParams;
  const id = typeof otherAddaId === "string" ? otherAddaId : "";
  return <OtherAddaAccount key={id} otherAddaId={id} />;
}
