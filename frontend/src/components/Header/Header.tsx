import styles from "./Header.module.css"
import { Htag } from "../"
import { HeaderProps } from "./Header.props"

export const Header = ({ ...props }: HeaderProps) => {
    return (
        <div className={styles.header} {...props}>
            <Htag tag='h1'>Header</Htag>
        </div>
    )
}
