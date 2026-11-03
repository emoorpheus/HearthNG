import {useCallback} from 'preact/hooks';
import {useKeys, type NavKey} from '../hooks/useKeys';
import {useOkPress} from '../hooks/useOkPress';

// LG-style edit mode (hold OK on an app or input on the home screen): arrows either side of the tile move it along the
// row, round buttons above it hide it, uninstall it (apps) or open the full menu (to the start or end, favourites).
// The tile stays where it is on the row; the buttons are drawn by the tile itself (EditDecor), the keys are read here.

export type EditActionKind = 'hide' | 'uninstall' | 'more';

export interface EditAction {
	kind: EditActionKind;
	label: string;
	/** greyed out, with the reason shown when it is focused (e.g. a system app cannot be uninstalled) */
	disabled?: string | null;
}

/** What the tile being edited draws round itself. */
export interface TileEditView {
	key: string;
	/** a move left / right is possible from here */
	left: boolean;
	right: boolean;
	actions: EditAction[];
	/** -1 = the tile itself (arrows move it), 0.. = that button above the tile */
	at: number;
	onMove: (dir: 'left' | 'right') => void;
	onAction: (index: number) => void;
}

const PATHS: Record<EditActionKind | 'left' | 'right', string> = {
	// an eye with a line through it
	hide: 'M3 12s3.5-6.5 9-6.5S21 12 21 12s-3.5 6.5-9 6.5S3 12 3 12z M12 9.2a2.8 2.8 0 1 0 0 5.6a2.8 2.8 0 1 0 0-5.6z M4.5 4.5l15 15',
	// a bin
	uninstall: 'M4.5 6.5h15 M9.5 6.5V4.5h5v2 M6.5 6.5l1 13h9l1-13 M10.5 10v6.5 M13.5 10v6.5',
	// three dots
	more: 'M6 12h.01 M12 12h.01 M18 12h.01',
	left: 'M14.5 6l-6 6l6 6',
	right: 'M9.5 6l6 6l-6 6'
};

function EditIcon ({name}: {name: keyof typeof PATHS}) {
	return (
		<svg class={`tile-edit__icon tile-edit__icon--${name}`} viewBox="0 0 24 24" aria-hidden="true">
			<path d={PATHS[name]} />
		</svg>
	);
}

/** Drawn inside the tile being edited: the two arrows and the row of buttons above it. */
export function EditDecor ({view}: {view: TileEditView}) {
	const onTile = view.at < 0;
	return (
		<div class={`tile-edit${onTile ? ' tile-edit--on-tile' : ''}`}>
			<div class="tile-edit__actions">
				{view.actions.map((a, i) => (
					<div
						key={a.kind}
						class={`tile-edit__action${i === view.at ? ' tile-edit__action--focused' : ''}${a.disabled ? ' tile-edit__action--disabled' : ''}`}
						onClick={(e) => { e.stopPropagation(); view.onAction(i); }}
					>
						<EditIcon name={a.kind} />
					</div>
				))}
			</div>
			<div class={`tile-edit__arrow tile-edit__arrow--left${view.left ? '' : ' tile-edit__arrow--off'}`} onClick={(e) => { e.stopPropagation(); if (view.left) view.onMove('left'); }}>
				<EditIcon name="left" />
			</div>
			<div class={`tile-edit__arrow tile-edit__arrow--right${view.right ? '' : ' tile-edit__arrow--off'}`} onClick={(e) => { e.stopPropagation(); if (view.right) view.onMove('right'); }}>
				<EditIcon name="right" />
			</div>
		</div>
	);
}

interface KeysProps {
	view: TileEditView;
	setAt: (at: number) => void;
	onDone: () => void;
	/** the line at the top of the screen: what the keys do now */
	hint: string;
}

/** Reads the remote while a tile is being edited, and shows what the keys do.
 *  On the tile: Left / Right move it, Up goes to the buttons, OK or Back ends. On the buttons: Left / Right pick one,
 *  OK uses it, Down goes back to the tile, Back ends. */
export function TileEditKeys ({view, setAt, onDone, hint}: KeysProps) {
	const n = view.actions.length;
	const handleKey = useCallback((key: NavKey, event: KeyboardEvent): boolean => {
		const at = view.at;
		if (at < 0 && (key === 'left' || key === 'right') && event && event.repeat) return true;   // one step per press
		switch (key) {
			case 'left':
				if (at < 0) { if (view.left) view.onMove('left'); } else setAt(Math.max(0, at - 1));
				break;
			case 'right':
				if (at < 0) { if (view.right) view.onMove('right'); } else setAt(Math.min(n - 1, at + 1));
				break;
			case 'up': if (at < 0 && n > 0) setAt(0); break;
			case 'down': if (at >= 0) setAt(-1); break;
			case 'back': onDone(); break;
			default: break;
		}
		return true;
	}, [view, n, setAt, onDone]);
	useKeys(handleKey, true);
	useOkPress({
		onPress: () => { if (view.at < 0) onDone(); else view.onAction(view.at); },
		onLongPress: () => onDone()
	}, true);
	return <div class="tile-edit__hint">{hint}</div>;
}
