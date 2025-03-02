import { PProps } from './P.props';
import styles from './P.module.css';
import cn from 'classnames';

export const P = ({ size = 'medium', children, className, ...props}: PProps) => {
	return(
		<p 
			className={cn(styles.p, className, {
				[styles.small]: size == 'small',
				[styles.medium]: size == 'medium',
				[styles.large]: size == 'large'
			})}
			{...props}
		>
			{children}
		</p>
	);
};