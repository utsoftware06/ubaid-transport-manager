"use client";

import { useLanguage } from "@/contexts/LanguageContext";
import VoiceTypingField from "@/components/shared/VoiceTypingField";
import { formatAmount } from "./Workshop";
import { WORKSHOP_WORK_TYPE_GROUPS, getWorkCategory, getWorkTypeLabel, type WorkshopWorkItem } from "./workshopWorkTypes";

type Props = { items: WorkshopWorkItem[]; onChange: (items: WorkshopWorkItem[]) => void };

export default function WorkshopWorkItems({ items, onChange }: Props) {
  const { t, dir } = useLanguage();
  const options = WORKSHOP_WORK_TYPE_GROUPS.flatMap(([category, workTypes]) => workTypes.map((workType) => ({ category, workType, label: getWorkTypeLabel(workType, t) })));
  const update = (index: number, patch: Partial<WorkshopWorkItem>) => onChange(items.map((item, current) => current === index ? { ...item, ...patch } : item));

  return <section dir={dir} className="mt-6 rounded-xl border border-gray-300 bg-white p-4 shadow-sm md:p-5">
    <div className="flex flex-wrap items-center justify-between gap-3"><div><h3 className="text-xl font-black text-gray-900">{t("workshop.workItems.title")}</h3><p className="text-sm font-semibold text-gray-700">{t("workshop.workItems.description")}</p></div><button type="button" onClick={() => onChange([...items, { clientId: crypto.randomUUID(), workType: "", category: "", quantity: "1", rate: "0", amount: 0, remarks: "" }])} className="rounded-lg bg-blue-600 px-5 py-3 font-bold text-white hover:bg-blue-700">+ {t("workshop.workItems.add")}</button></div>
    <datalist id="workshop-work-types">{options.map((option) => <option key={option.workType} value={option.label}>{t(`workshop.workItems.categories.${option.category}`)}</option>)}</datalist>
    <div className="mt-4 space-y-3">{items.map((item, index) => {
      const displayed = item.workType ? getWorkTypeLabel(item.workType, t) : "";
      return <div key={item.clientId} className="grid grid-cols-1 gap-3 rounded-lg border border-gray-300 bg-white p-4 md:grid-cols-12">

        <VoiceTypingField fieldLabel={t("workshop.workItems.searchPlaceholder")} mode="text"><label className="font-bold text-gray-900 md:col-span-4"><span className="mb-2 block">{t("workshop.workItems.workType")}</span><input list="workshop-work-types" value={displayed} onChange={(event) => { const option=options.find((candidate)=>candidate.label.toLowerCase()===event.target.value.trim().toLowerCase()); update(index,{workType:option?.workType ?? event.target.value,category:option?.category ?? getWorkCategory(event.target.value)}); }} placeholder={t("workshop.workItems.searchPlaceholder")} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3 font-semibold text-gray-900 placeholder:text-gray-600" />{item.category && <small className="mt-1 block text-gray-700">{t(`workshop.workItems.categories.${item.category}`)}</small>}</label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("workshop.workItems.quantity")} mode="number"><label className="font-bold text-gray-900 md:col-span-2"><span className="mb-2 block">{t("workshop.workItems.quantity")}</span><input type="number" min="0.01" step="any" dir="ltr" value={item.quantity} onChange={(event)=>{const quantity=event.target.value;update(index,{quantity,amount:Number(quantity||0)*Number(item.rate||0)});}} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>


        <VoiceTypingField fieldLabel={t("workshop.workItems.rate")} mode="amount"><label className="font-bold text-gray-900 md:col-span-2"><span className="mb-2 block">{t("workshop.workItems.rate")}</span><input type="number" min="0" step="any" dir="ltr" value={item.rate} onChange={(event)=>{const rate=event.target.value;update(index,{rate,amount:Number(item.quantity||0)*Number(rate||0)});}} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></label></VoiceTypingField>

        <div className="md:col-span-2"><span className="mb-2 block font-bold text-gray-900">{t("workshop.workItems.amount")}</span><div dir="ltr" className="rounded-lg border border-blue-200 bg-blue-50 px-3 py-3 font-black text-gray-900">{formatAmount(item.amount)}</div></div>
        <button type="button" aria-label={`${t("workshop.workItems.remove")} ${index+1}`} onClick={()=>onChange(items.filter((_,current)=>current!==index))} className="self-end rounded-lg bg-red-600 px-3 py-3 font-bold text-white md:col-span-2">{t("workshop.workItems.remove")}</button>
        <label className="font-bold text-gray-900 md:col-span-12"><span className="mb-2 block">{t("workshop.workItems.remarks")}</span><VoiceTypingField fieldLabel={t("workshop.workItems.remarks")} value={item.remarks} onValueChange={(remarks)=>update(index,{remarks})} contextKey={item.clientId}><input value={item.remarks} onChange={(event)=>update(index,{remarks:event.target.value})} className="w-full rounded-lg border border-gray-300 bg-white px-3 py-3" /></VoiceTypingField></label>
      </div>;
    })}</div>
    <div className="mt-4 flex justify-end rounded-lg border border-blue-200 bg-blue-50 p-4 text-xl font-black text-gray-900"><span>{t("workshop.workItems.grandTotal")}: </span><span dir="ltr" className="ms-3">{formatAmount(items.reduce((sum,item)=>sum+item.amount,0))}</span></div>
  </section>;
}
