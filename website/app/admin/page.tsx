import AdminClient from "./admin-client";
import Link from "next/link";
import Image from "next/image";

export const metadata = {
  title: "运营后台 · MacPulse",
  robots: { index: false, follow: false },
};

export default function AdminPage() {
  return (
    <main className="admin-page">
      <nav className="nav shell" aria-label="后台导航">
        <Link className="brand" href="/">
          <Image className="brand-icon" src="/icon.png" width={26} height={26} alt="" unoptimized />
          <span>MACPULSE // ADMIN</span>
        </Link>
        <div className="nav-links"><Link href="/rankings">公开榜单</Link><Link href="/">首页</Link></div>
      </nav>
      <AdminClient />
    </main>
  );
}
