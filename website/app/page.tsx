import Content from "./home-content";
import { localizedMetadata } from "./locale-server";
export const generateMetadata = () => localizedMetadata("/");
export default function Page() { return <Content />; }
