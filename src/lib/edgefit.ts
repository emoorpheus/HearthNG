// Keeps something drawn round a tile on the screen: the round buttons above the tile being edited are centred over it,
// so for a tile at the screen edge (the first one) they would reach past the edge and the outer button would be cut off.

/** How far (px, + = right) a box from `left` that is `width` wide has to move to stay `edge` px inside a screen
 *  `screen` px wide. 0 when it already fits or nothing usable was measured; a box wider than the room starts at the
 *  left margin. */
export function edgeShift (left: number, width: number, screen: number, edge: number): number {
	if (!isFinite(left) || !isFinite(width) || !isFinite(screen) || width <= 0 || screen <= 0) return 0;
	const min = edge;
	const max = screen - edge - width;
	if (max < min || left < min) return min - left;
	if (left > max) return max - left;
	return 0;
}
