import styles from './loading.module.css';
import Image from 'next/image';

export default function Loading() {
	return (
		<div className={styles.loading}>
			<Image src="/loading.svg" alt="Loading" width={100} height={100} />
		</div>
	);
}