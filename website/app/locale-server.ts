import { cookies } from "next/headers";
import { pageCopy, type Locale } from "./locale";
export async function requestLocale(): Promise<Locale> {
  return (await cookies()).get("tokenmini-language")?.value === "zh" ? "zh" : "en";
}
export async function localizedMetadata(path: string) {
  const locale = await requestLocale();
  const copy = pageCopy(path, locale);
  return { ...copy, alternates: { canonical: `https://tokenmini.cc${path}` }, openGraph: {
    ...copy, url: `https://tokenmini.cc${path}`, siteName: "TokenMini", type: "website" as const,
    locale: locale === "zh" ? "zh_CN" : "en_US",
    images: [{ url: "/brand/motion-v2/frame-00.png", width: 1672, height: 941, alt: "TokenMini" }],
  } };
}
