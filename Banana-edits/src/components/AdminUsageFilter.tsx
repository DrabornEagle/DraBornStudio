import React, { useState } from 'react';
import {
  ADMIN_USAGE_PRESETS, AdminUsagePeriod, AdminUsagePreset, AdminUsageRange,
  describeAdminUsageRange, localDateInput, resolveAdminUsageRange,
} from '../lib/admin/adminUsageRange';

export const AdminUsageFilter = ({ period, range, onChange }: {
  period: AdminUsagePeriod;
  range?: AdminUsageRange;
  onChange: (period: AdminUsagePeriod) => void;
}) => {
  const [preset, setPreset] = useState<AdminUsagePreset>(period.preset);
  const [from, setFrom] = useState(() => period.preset === 'custom' ? period.from
    : localDateInput(new Date(resolveAdminUsageRange({ preset: '30d' })!.start)));
  const [to, setTo] = useState(() => period.preset === 'custom' ? period.to : localDateInput(new Date()));
  let dateError = '';
  if (preset === 'custom') {
    try { resolveAdminUsageRange({ preset, from, to }); }
    catch (error) { dateError = (error as Error).message; }
  }
  const fieldClass = 'min-h-11 w-full min-w-0 rounded-lg border border-gray-700 bg-gray-900 px-3 py-2 text-base text-white outline-none focus:border-violet-400 focus:ring-1 focus:ring-violet-400 sm:text-sm [color-scheme:dark]';
  return <section aria-label="Usage time range" className="border-b border-gray-800 bg-gray-900/30 p-4 sm:px-6">
    <form onSubmit={event => {
      event.preventDefault();
      if (preset === 'custom' && !dateError) onChange({ preset, from, to });
    }} className="flex flex-col gap-3 sm:flex-row sm:flex-wrap sm:items-end">
      <div className="min-w-0 sm:w-44">
        <label htmlFor="admin-usage-period" className="mb-1.5 block text-xs font-medium text-gray-300">Time range</label>
        <select id="admin-usage-period" value={preset} className={fieldClass} onChange={event => {
          const next = event.target.value as AdminUsagePreset;
          setPreset(next);
          if (next !== 'custom') onChange({ preset: next });
        }}>
          {ADMIN_USAGE_PRESETS.map(option => <option key={option.value} value={option.value}>{option.label}</option>)}
        </select>
      </div>
      {preset === 'custom' && <>
        <div className="grid min-w-0 flex-1 grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="min-w-0">
            <label htmlFor="admin-usage-from" className="mb-1.5 block text-xs font-medium text-gray-300">Start date</label>
            <input id="admin-usage-from" type="date" required value={from} onChange={event => setFrom(event.target.value)} className={fieldClass} aria-invalid={!!dateError} aria-describedby={dateError ? 'admin-usage-date-error' : undefined} />
          </div>
          <div className="min-w-0">
            <label htmlFor="admin-usage-to" className="mb-1.5 block text-xs font-medium text-gray-300">End date</label>
            <input id="admin-usage-to" type="date" required value={to} onChange={event => setTo(event.target.value)} className={fieldClass} aria-invalid={!!dateError} aria-describedby={dateError ? 'admin-usage-date-error' : undefined} />
          </div>
        </div>
        <button type="submit" disabled={!!dateError} className="min-h-11 rounded-lg bg-violet-600 px-4 py-2 text-sm font-medium text-white hover:bg-violet-500 disabled:cursor-not-allowed disabled:opacity-40">Apply</button>
      </>}
    </form>
    {dateError && <p id="admin-usage-date-error" role="alert" className="mt-2 text-xs text-amber-300">{dateError}</p>}
    <p role="status" className="mt-3 text-xs text-gray-300">Showing: {describeAdminUsageRange(range)} <span className="text-gray-500">· {Intl.DateTimeFormat().resolvedOptions().timeZone}</span></p>
    <p className="mt-1 text-[11px] leading-relaxed text-gray-500">Applies to app totals and each user's model breakdown. {preset === 'custom' && 'Dates include the full end day; press Apply to update.'}</p>
  </section>;
};
