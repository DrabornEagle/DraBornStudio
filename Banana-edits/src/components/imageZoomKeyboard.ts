export type ImageZoomCommand = 'in' | 'out' | 'fit';

/** Plain keys inspect the image; browser zoom, editing and nested controls keep their keys. */
export function getImageZoomCommand(event: {
  key: string; defaultPrevented?: boolean; isComposing?: boolean; repeat?: boolean;
  ctrlKey?: boolean; metaKey?: boolean; altKey?: boolean;
}, blocked = false): ImageZoomCommand | null {
  if (blocked || event.defaultPrevented || event.isComposing || event.repeat || event.ctrlKey || event.metaKey || event.altKey) return null;
  if (event.key === '+' || event.key === '=') return 'in';
  if (event.key === '-') return 'out';
  if (event.key === '0') return 'fit';
  return null;
}
