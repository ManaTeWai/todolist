import type { Metadata } from "next"
import { Footer, Header, Sidebar } from "@/components"
import "./globals.css"
import styles from "./Layout.module.css"

export const metadata: Metadata = {
    title: "Todolist",
    description: "Local todolist app",
}

export default function RootLayout({
    children,
}: Readonly<{
    children: React.ReactNode
}>) {
    return (
        <html lang='ru'>
            <body className={styles.wrapper}>
                <Header className={styles.header} />
                <Sidebar className={styles.sidebar} />
                <main className={styles.body}>
                  {children}
                  </main>
                <Footer className={styles.footer} />
            </body>
        </html>
    )
}
