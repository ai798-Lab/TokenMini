import Content from "./rankings-content";
import { localizedMetadata } from "../locale-server";
export const generateMetadata = () => localizedMetadata("/rankings");
export default function Page() { return <Content />; }
