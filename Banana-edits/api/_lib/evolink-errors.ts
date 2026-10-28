// EvoLink can wrap a useful model error inside a generic gateway error.
// Always return text (never an object which becomes "[object Object]").
const genericError = /^(?:internal[ _-](?:server[ _-])?error|generation failed|video generation failed|api[ _-]error|unknown error)$/i;

const errorText = (value: unknown, depth = 0): string[] => {
  if (depth > 6 || value == null) return [];
  if (typeof value === 'string') return value.trim() ? [value.trim()] : [];
  if (Array.isArray(value)) return value.flatMap(item => errorText(item, depth + 1));
  if (typeof value !== 'object') return [];
  const data = value as Record<string, unknown>;
  return ['detail', 'details', 'reason', 'error_message', 'failure_reason', 'fail_reason', 'error', 'message', 'description', 'code']
    .flatMap(key => errorText(data[key], depth + 1));
};

export const getEvoLinkErrorMessage = (data: unknown, fallback = 'Video generation failed'): string => {
  const value = data as any;
  const candidates = [
    ...errorText(value?.error),
    ...errorText(value?.error_message),
    ...errorText(value?.failure_reason),
    ...errorText(value?.fail_reason),
    ...errorText(value?.task_info),
    ...errorText(value?.status_message),
    ...errorText(value?.message),
    ...(typeof data === 'string' ? errorText(data) : []),
  ];
  return candidates.find(message => !genericError.test(message)) || candidates[0] || fallback;
};

export const describeEvoLinkFailure = (
  data: unknown,
  context: string,
  taskId?: string,
): string => {
  const message = getEvoLinkErrorMessage(data);
  const detail = genericError.test(message)
    ? `The video provider returned an internal error without a specific reason. ${taskId ? 'Check the source video and contact support with this task ID if it persists.' : 'No task ID was received; check provider task history before retrying.'}`
    : message;
  return `${context}: ${detail}${taskId ? ` (Task: ${taskId})` : ''}`;
};
