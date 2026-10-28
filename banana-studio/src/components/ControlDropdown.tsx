import React, { useEffect, useId, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Check, ChevronDown } from 'lucide-react';

// Shared toolbar dropdown: image, video and Sunburst use the same control.
interface DropdownProps {
  label: string;
  value: string;
  options: { label: string; value: string; disabled?: boolean }[];
  onSelect: (value: any) => void;
  icon?: React.ElementType;
  compact?: boolean;
  disabled?: boolean;
}

export const Dropdown: React.FC<DropdownProps> = ({ label, value, options, onSelect, icon: Icon, compact, disabled = false }) => {
  const [isOpen, setIsOpen] = useState(false);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);
  const optionRefs = useRef(new Map<number, HTMLButtonElement>());
  const activeIndex = useRef(0);
  const menuId = useId();
  const [menuStyle, setMenuStyle] = useState<React.CSSProperties>({});

  const closeMenu = (restoreFocus = false) => {
    setIsOpen(false);
    if (restoreFocus) triggerRef.current?.focus({ preventScroll: true });
  };
  const focusOption = (index: number) => {
    activeIndex.current = index;
    optionRefs.current.get(index)?.focus({ preventScroll: true });
  };
  const openMenu = (last = false) => {
    if (disabled) return;
    const enabled = options.flatMap((option, index) => option.disabled ? [] : [index]);
    const selected = options.findIndex(option => option.value === value && !option.disabled);
    activeIndex.current = last ? enabled.at(-1) ?? 0 : selected >= 0 ? selected : enabled[0] ?? 0;
    setIsOpen(true);
  };

  useEffect(() => {
    if (!isOpen || !triggerRef.current) return;
    const positionMenu = () => {
        if (!triggerRef.current) return;
        const rect = triggerRef.current.getBoundingClientRect();
        const menuHeight = Math.min(300, options.length * 43 + 12);
        const openBelow = rect.top - 16 < menuHeight && window.innerHeight - rect.bottom > rect.top;
        setMenuStyle({
            position: 'fixed',
            left: `${Math.max(8, Math.min(rect.left, window.innerWidth - Math.max(rect.width, 160) - 8))}px`,
            ...(openBelow ? { top: `${rect.bottom + 8}px` } : { bottom: `${window.innerHeight - rect.top + 8}px` }),
            width: `${Math.max(rect.width, 160)}px`,
            maxHeight: `${Math.max(80, (openBelow ? window.innerHeight - rect.bottom : rect.top) - 16)}px`,
            zIndex: 9999,
        });
    };
    positionMenu();
    const frame = requestAnimationFrame(() => focusOption(activeIndex.current));
    window.addEventListener('resize', positionMenu);
    window.addEventListener('scroll', positionMenu, true);
    return () => { cancelAnimationFrame(frame); window.removeEventListener('resize', positionMenu); window.removeEventListener('scroll', positionMenu, true); };
  }, [isOpen, options.length]);

  useEffect(() => {
    if (disabled) setIsOpen(false);
  }, [disabled]);

  const selectedLabel = options.find(o => o.value === value)?.label || value;

  return (
    <>
      <button
        type="button"
        ref={triggerRef}
        title={label}
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={isOpen}
        aria-controls={isOpen ? menuId : undefined}
        disabled={disabled}
        onClick={event => { event.stopPropagation(); if (isOpen) closeMenu(); else openMenu(); }}
        onKeyDown={event => {
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') { event.preventDefault(); event.stopPropagation(); openMenu(event.key === 'ArrowUp'); }
          if (event.key === 'Escape' && isOpen) { event.preventDefault(); event.stopPropagation(); closeMenu(true); }
        }}
        className={`flex shrink-0 items-center justify-between gap-2 rounded-xl border bg-[#171e28] transition-all text-xs font-medium ${
            compact ? 'px-2.5 py-1.5 h-[42px] min-w-0' : 'px-3 py-2.5 h-[50px] min-w-[140px]'
        } ${isOpen ? 'border-violet-400/40 text-white ring-2 ring-violet-500/10' : 'border-white/[0.07] text-gray-300 hover:border-white/15 hover:bg-[#1b2330] hover:text-white'} focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-violet-400/50 disabled:cursor-not-allowed disabled:opacity-40`}
      >
        <div className="flex items-center gap-2 overflow-hidden">
            {Icon && <Icon className={`${compact ? 'w-3.5 h-3.5' : 'w-4 h-4'} text-gray-500 shrink-0`} />}
            <div className="flex flex-col items-start truncate">
                 {!compact && <span className="text-[9px] text-gray-500 uppercase tracking-wider font-bold leading-none mb-0.5">{label}</span>}
                 <span className={`truncate font-semibold ${compact ? 'text-xs' : 'text-sm'}`}>{selectedLabel}</span>
            </div>
        </div>
        <ChevronDown className={`w-3.5 h-3.5 text-gray-500 transition-transform duration-200 shrink-0 ${isOpen ? 'rotate-180' : ''}`} />
      </button>

      {isOpen && createPortal(
        <>
        <div className="fixed inset-0 z-[9998]" aria-hidden="true" data-control-dropdown-dismiss onMouseDown={event => event.stopPropagation()} onClick={event => { event.stopPropagation(); closeMenu(true); }} />
        <div
            id={menuId}
            role="menu"
            aria-label={label}
            ref={menuRef}
            style={menuStyle}
            className="bg-[#0d1117] border border-gray-700 rounded-xl shadow-2xl p-1.5 animate-in slide-in-from-bottom-2 fade-in duration-200 overflow-y-auto"
            onClick={event => event.stopPropagation()}
            onMouseDown={event => event.stopPropagation()}
            onKeyDown={event => {
              event.stopPropagation();
              if (event.key === 'Escape') { event.preventDefault(); closeMenu(true); return; }
              if (event.key === 'Tab') { closeMenu(true); return; }
              const enabled = options.flatMap((option, index) => option.disabled ? [] : [index]);
              if (!enabled.length) return;
              if (['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key)) {
                event.preventDefault();
                const current = Math.max(0, enabled.indexOf(activeIndex.current));
                const next = event.key === 'Home' ? 0 : event.key === 'End' ? enabled.length - 1 : (current + (event.key === 'ArrowDown' ? 1 : -1) + enabled.length) % enabled.length;
                focusOption(enabled[next]);
              }
              if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') event.preventDefault();
            }}
        >
            <div className="max-h-[300px] overflow-y-auto no-scrollbar">
                {options.map((opt, index) => (
                    <button
                        type="button"
                        key={opt.value}
                        ref={element => { if (element) optionRefs.current.set(index, element); else optionRefs.current.delete(index); }}
                        role="menuitemradio"
                        aria-checked={opt.value === value}
                        tabIndex={activeIndex.current === index ? 0 : -1}
                        onFocus={() => { activeIndex.current = index; }}
                        onClick={() => {
                            if (!opt.disabled && !disabled) {
                                onSelect(opt.value);
                                closeMenu(true);
                            }
                        }}
                        disabled={opt.disabled}
                        className={`w-full text-left px-3 py-2.5 rounded-lg text-xs font-medium flex items-center justify-between transition-colors mb-0.5 last:mb-0 ${
                            opt.value === value
                            ? 'bg-gray-800 text-white'
                            : (opt.disabled ? 'text-gray-700 cursor-not-allowed' : 'text-gray-400 hover:bg-gray-800/50 hover:text-gray-200')
                        }`}
                    >
                        <span>{opt.label}</span>
                        {opt.value === value && <Check className="w-3.5 h-3.5 text-violet-400" />}
                    </button>
                ))}
            </div>
        </div>
        </>,
        document.body
      )}
    </>
  );
};
