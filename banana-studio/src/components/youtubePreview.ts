export const DESKTOP_PREVIEW_WIDTHS = [1280, 1440, 1600, 1920, 2560] as const;
export const MOBILE_PREVIEW_WIDTHS = [320, 360, 390, 430] as const;
export type PreviewDevice = 'desktop' | 'mobile';

/** Measured on youtube.com on 2026-09-25; see docs/youtube-preview.md.
 * Wide home feeds retain three columns, capped at 700px per thumbnail.
 * Mobile models the responsive website, not a claim about the native app.
 */
export function getPreviewLayout(device: PreviewDevice, width: number) {
  const columns = device === 'mobile' ? 1 : 3;
  const sidebar = device === 'mobile' ? 0 : width > 1312 ? 240 : 72;
  const padding = device === 'mobile' ? 20 : 24;
  const gap = device === 'mobile' ? 0 : 16;
  const feedWidth = Math.min(width - sidebar - padding * 2, 2132);
  const thumbnailWidth = (feedWidth - gap * (columns - 1)) / columns;
  return { columns, sidebar, padding, gap, feedWidth, thumbnailWidth, thumbnailHeight: thumbnailWidth * 9 / 16 };
}

// Fictional, locally authored examples. No external channel photos or tracking requests.
export const PREVIEW_EXAMPLES = [
  {
    "videoId": "example-1",
    "title": "CITY ADVENTURE",
    "channel": "Studio Atlas",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-1.svg",
    "avatar": "avatar.svg"
  },
  {
    "videoId": "example-2",
    "title": "THE BIG CHALLENGE",
    "channel": "Everyday Experiments",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-2.svg",
    "avatar": "avatar.svg"
  },
  {
    "videoId": "example-3",
    "title": "ONE WEEK AWAY",
    "channel": "Window Seat",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-3.svg",
    "avatar": "avatar.svg"
  },
  {
    "videoId": "example-4",
    "title": "AFTER HOURS",
    "channel": "Studio Atlas",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-4.svg",
    "avatar": "avatar.svg"
  },
  {
    "videoId": "example-5",
    "title": "INTO THE WILD",
    "channel": "Everyday Experiments",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-5.svg",
    "avatar": "avatar.svg"
  },
  {
    "videoId": "example-6",
    "title": "A NEW PERSPECTIVE",
    "channel": "Window Seat",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-6.svg",
    "avatar": "avatar.svg"
  },
  {
    "videoId": "example-7",
    "title": "CAN WE DO IT?",
    "channel": "Studio Atlas",
    "views": "1.2M",
    "age": "1w ago",
    "duration": "12:34",
    "image": "example-7.svg",
    "avatar": "avatar.svg"
  }
] as const;
