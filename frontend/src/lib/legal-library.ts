// Shared definitions for the Saudi Legal Library section.
// URL configuration is persisted in localStorage; users edit it from Settings.

export type LawId =
  | "civil"
  | "labor"
  | "companies"
  | "investment"
  | "commercial"
  | "evidence"
  | "execution";

export type LawDef = {
  id: LawId;
  title: string;
  short: string;
  description: string;
  /** Tailwind gradient classes for the card face (luxurious, high contrast) */
  gradient: string;
  /** Glow color for hover ring */
  glow: string;
  /** Default reference URL (user can override from Settings) */
  defaultUrl: string;
  /** System prompt context used when asking AI within this law */
  context: string;
};

export const LAWS: LawDef[] = [
  {
    id: "civil",
    title: "نظام المعاملات المدنية",
    short: "المعاملات المدنية",
    description: "العقود، الالتزامات، المسؤولية التقصيرية، وأحكام المعاملات بين الأفراد.",
    gradient: "from-indigo-600 via-blue-600 to-cyan-500",
    glow: "shadow-[0_20px_60px_-15px_rgba(59,130,246,0.55)]",
    defaultUrl: "https://nezams.com/%D9%86%D8%B8%D8%A7%D9%85-%D8%A7%D9%84%D9%85%D8%B9%D8%A7%D9%85%D9%84%D8%A7%D8%AA-%D8%A7%D9%84%D9%85%D8%AF%D9%86%D9%8A%D8%A9/",
    context: "نظام المعاملات المدنية السعودي الصادر بالمرسوم الملكي رقم م/191 وتاريخ 29/11/1444هـ.",
  },
  {
    id: "labor",
    title: "نظام العمل",
    short: "العمل",
    description: "علاقات العمل، الأجور، الإجازات، إنهاء العقد، ومكافأة نهاية الخدمة.",
    gradient: "from-emerald-600 via-teal-600 to-cyan-500",
    glow: "shadow-[0_20px_60px_-15px_rgba(16,185,129,0.55)]",
    defaultUrl: "https://www.hrdf.org.sa/media/pn1bh3vm/%D9%86%D8%B8%D8%A7%D9%85-%D8%A7%D9%84%D8%B9%D9%85%D9%84.pdf",
    context: "نظام العمل السعودي وتعديلاته بما في ذلك أحكام عقد العمل، الأجور، الإجازات، وإنهاء الخدمة.",
  },
  {
    id: "companies",
    title: "نظام الشركات",
    short: "الشركات",
    description: "تأسيس الشركات، أنواعها، حوكمتها، الاندماج، التصفية، ومسؤولية الشركاء.",
    gradient: "from-violet-600 via-purple-600 to-fuchsia-500",
    glow: "shadow-[0_20px_60px_-15px_rgba(168,85,247,0.55)]",
    defaultUrl: "https://nezams.com/%D9%86%D8%B8%D8%A7%D9%85-%D8%A7%D9%84%D8%B4%D8%B1%D9%83%D8%A7%D8%AA-%D9%84%D8%B9%D8%A7%D9%85-%D9%A1%D9%A4%D9%A4%D9%A3%D9%87%D9%80/",
    context: "نظام الشركات السعودي الجديد الصادر بالمرسوم الملكي رقم م/132 وتاريخ 1/12/1443هـ.",
  },
  {
    id: "investment",
    title: "نظام الاستثمار",
    short: "الاستثمار",
    description: "تنظيم الاستثمار الأجنبي والمحلي، الحوافز، الضمانات، وفض المنازعات.",
    gradient: "from-amber-500 via-orange-500 to-rose-500",
    glow: "shadow-[0_20px_60px_-15px_rgba(249,115,22,0.55)]",
    defaultUrl: "https://nezams.com/%D9%86%D8%B8%D8%A7%D9%85-%D8%A7%D9%84%D8%A7%D8%B3%D8%AA%D8%AB%D9%85%D8%A7%D8%B1-%D8%A7%D9%84%D8%A3%D8%AC%D9%86%D8%A8%D9%8A/",
    context: "نظام الاستثمار السعودي وضوابطه التنفيذية الصادرة عن وزارة الاستثمار.",
  },
  {
    id: "commercial",
    title: "النظام التجاري",
    short: "التجاري",
    description: "الأعمال التجارية، التجار، الأوراق التجارية، الإفلاس، والوكالات.",
    gradient: "from-rose-600 via-pink-600 to-red-500",
    glow: "shadow-[0_20px_60px_-15px_rgba(244,63,94,0.55)]",
    defaultUrl: "https://laws.moj.gov.sa/ar/legislation/s6IDjaBqLFPEFLlY8MedIg",
    context: "الأنظمة التجارية السعودية بما يشمل نظام المحكمة التجارية، الأوراق التجارية، ونظام الإفلاس.",
  },
  {
    id: "evidence",
    title: "نظام الإثبات",
    short: "الإثبات",
    description: "طرق الإثبات في المعاملات والوقائع، البيّنة، الكتابة، القرائن، واليمين.",
    gradient: "from-sky-600 via-blue-600 to-indigo-600",
    glow: "shadow-[0_20px_60px_-15px_rgba(2,132,199,0.55)]",
    defaultUrl: "https://nezams.com/%D9%86%D8%B8%D8%A7%D9%85-%D8%A7%D9%84%D8%A5%D8%AB%D8%A8%D8%A7%D8%AA/",
    context: "نظام الإثبات السعودي الصادر بالمرسوم الملكي رقم م/43 وتاريخ 26/5/1443هـ.",
  },
  {
    id: "execution",
    title: "نظام التنفيذ",
    short: "التنفيذ",
    description: "إجراءات تنفيذ الأحكام والسندات، الحجز، المنع من السفر، والإفصاح.",
    gradient: "from-slate-700 via-zinc-700 to-stone-600",
    glow: "shadow-[0_20px_60px_-15px_rgba(71,85,105,0.55)]",
    defaultUrl: "https://nezams.com/%D9%86%D8%B8%D8%A7%D9%85-%D8%A7%D9%84%D8%AA%D9%86%D9%81%D9%8A%D8%B0/",
    context: "نظام التنفيذ السعودي ولائحته التنفيذية الصادرة عن وزارة العدل.",
  },
];

const LS_KEY = "legal-library-urls";

export function loadLibraryUrls(): Record<LawId, string> {
  const defaults = Object.fromEntries(LAWS.map((l) => [l.id, l.defaultUrl])) as Record<LawId, string>;
  if (typeof window === "undefined") return defaults;
  try {
    const raw = window.localStorage.getItem(LS_KEY);
    if (!raw) return defaults;
    const parsed = JSON.parse(raw) as Partial<Record<LawId, string>>;
    return { ...defaults, ...parsed };
  } catch {
    return defaults;
  }
}

export function saveLibraryUrls(urls: Record<LawId, string>) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(LS_KEY, JSON.stringify(urls));
}
