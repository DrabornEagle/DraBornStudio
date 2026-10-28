export const ADMIN_USAGE_PRESETS = [
  { value: 'all', label: 'All time' },
  { value: 'today', label: 'Today' },
  { value: 'yesterday', label: 'Yesterday' },
  { value: '7d', label: 'Last 7 days' },
  { value: '30d', label: 'Last 30 days' },
  { value: 'month', label: 'This month' },
  { value: 'custom', label: 'Custom dates' },
] as const;

export type AdminUsagePreset = typeof ADMIN_USAGE_PRESETS[number]['value'];
export type AdminUsagePeriod = { preset: Exclude<AdminUsagePreset, 'custom'> }
  | { preset: 'custom'; from: string; to: string };
/** Inclusive start, exclusive end. Undefined means all time. */
export interface AdminUsageRange { start: string; end: string }

export const localDateInput = (date: Date): string =>
  `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;

const parseLocalDate = (value: string): Date => {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error('Choose a start and end date.');
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(year, month - 1, day);
  if (localDateInput(date) !== value) throw new Error('Choose valid dates.');
  return date;
};

export const validateAdminUsageRange = (range?: AdminUsageRange): void => {
  if (range && (!Number.isFinite(Date.parse(range.start)) || !Number.isFinite(Date.parse(range.end))
    || Date.parse(range.start) >= Date.parse(range.end))) {
    throw new Error('Choose a valid time range.');
  }
};

export const resolveAdminUsageRange = (period: AdminUsagePeriod, now = new Date()): AdminUsageRange | undefined => {
  if (period.preset === 'all') return undefined;
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  if (period.preset === 'custom') {
    const from = parseLocalDate(period.from);
    const to = parseLocalDate(period.to);
    if (from > to) throw new Error('End date must be on or after start date.');
    // Calendar arithmetic includes the entire final day, including DST changes.
    to.setDate(to.getDate() + 1);
    return { start: from.toISOString(), end: to.toISOString() };
  }
  if (period.preset === 'yesterday') {
    end.setTime(start.getTime());
    start.setDate(start.getDate() - 1);
  } else if (period.preset === '7d') start.setDate(start.getDate() - 6);
  else if (period.preset === '30d') start.setDate(start.getDate() - 29);
  else if (period.preset === 'month') start.setDate(1);
  return { start: start.toISOString(), end: end.toISOString() };
};

export const describeAdminUsageRange = (range?: AdminUsageRange): string => {
  if (!range) return 'All time';
  const format = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
  const from = format.format(new Date(range.start));
  const to = format.format(new Date(Date.parse(range.end) - 1));
  return from === to ? from : `${from} – ${to}`;
};
