import styles from "./page.module.css";
import { Htag } from "@/components";

export default function Home() {
  return (
    <div className={styles.main}>
      <Htag tag="h1">Home</Htag>
    </div>
  );
}
