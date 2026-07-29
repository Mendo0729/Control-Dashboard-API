export const PROJECT_STATUSES = [
  'ACTIVE',
  'DEVELOPMENT',
  'MAINTENANCE',
  'PAUSED',
  'ARCHIVED',
] as const;

export type ProjectStatus = (typeof PROJECT_STATUSES)[number];
