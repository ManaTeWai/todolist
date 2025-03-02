import styles from "./Footer.module.css"
import { Htag } from "../"
import { FooterProps } from "./Footer.props"

export const Footer = ({ ...props }: FooterProps) => {
    return (
        <div className={styles.footer} {...props}>
            <Htag tag='h1'>Footer</Htag>
        </div>
    )
}
