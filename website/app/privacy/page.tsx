import Content from "./privacy-content";
import { localizedMetadata } from "../locale-server";
export const generateMetadata = () => localizedMetadata("/privacy");
export default function Page() { return <Content />; }
