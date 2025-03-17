import { Htag, P } from '@/components';
import styles from './not-found.module.css';
import Link from 'next/link';

export default function NotFound() {
	return (
		<div className={styles.not_found}>
			<Htag tag="h1">404</Htag>
			<P>Страница не найдена</P>
			<P size="large"><Link className={styles.link} href="/">Вернуться на главную</Link></P>
		</div>
	);
}