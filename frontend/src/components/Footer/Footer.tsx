import styles from "./Footer.module.css"
import { P } from "../"
import { FooterProps } from "./Footer.props"
import cn from "classnames"
import { format } from "date-fns"
import Link from 'next/link'

export const Footer = ({ className, ...props }: FooterProps) => {
    return (
        <footer className={cn(styles.footer, className)} {...props}>
            <P size='large'>
                ToDoList &copy; 2025 - {format(new Date(), "yyyy")}
            </P>

            <div className={styles.links}>
                <P size='large'><Link className={styles.link} href="/privacy">Политика конфиденциальности</Link></P>
                <P size='large'><Link className={styles.link} href="/policy">Пользовательское соглашение</Link></P>
            </div>
        </footer>
    )
}
