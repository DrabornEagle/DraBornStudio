export default {
 content: ['./index.html', './share.html', './src/**/*.{ts,tsx}'],
 theme: { extend: {
  colors: { gray: { 750: '#2d3748', 850: '#1a202c', 950: '#0d1117' } },
  animation: { 'pulse-fast': 'pulse 1.5s cubic-bezier(0.4, 0, 0.6, 1) infinite', 'progress-indeterminate': 'progress-indeterminate 1.5s infinite linear' },
  keyframes: { 'progress-indeterminate': { '0%': { transform: 'translateX(-100%)', width: '20%' }, '100%': { transform: 'translateX(400%)', width: '20%' } } }
 } }, plugins: []
};
