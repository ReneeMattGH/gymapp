import type { NextFunction, Request, RequestHandler, Response } from 'express';
import { ZodError } from 'zod';
import type { Logger } from 'pino';

export class AppError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const badRequest = (code: string, message: string) => new AppError(400, code, message);
export const unauthorized = (message = 'Authentication required.') =>
  new AppError(401, 'unauthorized', message);
export const forbidden = (message = 'You cannot perform this action.') =>
  new AppError(403, 'forbidden', message);
export const notFound = (message = 'Not found.') => new AppError(404, 'not_found', message);
export const conflict = (code: string, message: string) => new AppError(409, code, message);
export const serviceUnavailable = (code: string, message: string) =>
  new AppError(503, code, message);

/** Wraps an async handler so rejected promises reach the error middleware. */
export function asyncHandler(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
): RequestHandler {
  return (req, res, next) => {
    handler(req, res, next).catch(next);
  };
}

export function notFoundHandler(_req: Request, res: Response): void {
  res.status(404).json({ error: { code: 'not_found', message: 'Route not found.' } });
}

export function createErrorHandler(logger: Logger) {
  return (error: unknown, _req: Request, res: Response, _next: NextFunction): void => {
    if (res.headersSent) {
      return;
    }
    if (error instanceof ZodError) {
      res.status(400).json({
        error: {
          code: 'validation_error',
          message: 'The request body is invalid.',
          fields: error.issues.map((issue) => ({
            field: issue.path.join('.'),
            message: issue.message,
          })),
        },
      });
      return;
    }
    if (error instanceof AppError) {
      res.status(error.status).json({ error: { code: error.code, message: error.message } });
      return;
    }
    logger.error({ err: error }, 'unhandled request error');
    res.status(500).json({ error: { code: 'internal_error', message: 'Something went wrong.' } });
  };
}
