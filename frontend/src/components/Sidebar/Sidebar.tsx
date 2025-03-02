import { Htag } from "../"
import styles from './Sidebar.module.css'
import { SidebarProps } from "./Sidebar.props"

export const Sidebar = ({ ...props }: SidebarProps) => {
    return (
        <div className={styles.sidebar} {...props}>
            <Htag tag='h1'>Sidebar</Htag>
        </div>
    )
}
