import express, { Router, type Request } from 'express';
import { z } from 'zod';
import { badRequest, asyncHandler, unauthorized } from '../errors.js';
import type { CommunityService, CommunityViewer } from './service.js';

const limitSchema = z.coerce.number().int().min(1).max(50).optional();
const offsetSchema = z.coerce.number().int().min(0).optional();

function viewer(req: Request): CommunityViewer {
  if (!req.auth) throw unauthorized();
  return { userId: req.auth.userId, email: req.auth.email };
}

const idsSchema = z.object({
  id: z.string().uuid(),
});

const profileSchema = z.object({
  username: z.string().trim().max(60),
  displayName: z.string().trim().min(2).max(50),
  bio: z.string().trim().max(280).nullish(),
  interests: z.array(z.string().trim().min(1).max(40)).max(8).default([]),
  categories: z.array(z.string().trim().min(1).max(40)).max(8).default([]),
  avatarURL: z.string().trim().max(500).nullish(),
  age: z.number().int().min(13).max(100).nullish(),
});

const preferencesSchema = z.object({
  discoverable: z.boolean(),
  showGym: z.boolean(),
  showArea: z.boolean(),
  showCity: z.boolean().default(true),
  showCountry: z.boolean().default(true),
  nearbyDiscovery: z.boolean(),
  globalDiscovery: z.boolean().default(true),
  allowConnectionRequests: z.boolean(),
  allowMessages: z.boolean(),
  notifyConnections: z.boolean(),
  notifyMessages: z.boolean(),
  notifyComments: z.boolean(),
  notifyLikes: z.boolean(),
});

const postSchema = z.object({
  id: z.string().uuid(),
  content: z.string().min(1).max(2000),
  kind: z.enum(['update', 'workout', 'milestone', 'achievement', 'motivation']),
  sessionId: z.string().max(64).nullish(),
  achievementLabel: z.string().trim().max(80).nullish(),
  session: z
    .object({
      sessionId: z.string().max(64),
      title: z.string().trim().min(1).max(120),
      startedAt: z.string().min(1).max(40).nullish(),
      durationSeconds: z.number().int().min(0).max(86_400),
    })
    .nullish(),
});

export function createCommunityRouter(options: {
  service: CommunityService;
  requireAuth: import('express').RequestHandler;
}): Router {
  const { service, requireAuth } = options;
  const router = Router();
  router.use(requireAuth);

  router.get(
    '/bootstrap',
    asyncHandler(async (req, res) => {
      res.json(await service.bootstrap(viewer(req)));
    }),
  );

  router.get(
    '/discover',
    asyncHandler(async (req, res) => {
      const scope = z
        .enum(['gym', 'area', 'city', 'region', 'country', 'global', 'all'])
        .parse(req.query.scope ?? 'gym');
      res.json(
        await service.discover(viewer(req), {
          scope,
          query: String(req.query.q ?? ''),
          interest: String(req.query.interest ?? ''),
          country: String(req.query.country ?? ''),
          city: String(req.query.city ?? ''),
          gymId: req.query.gym_id ? String(req.query.gym_id) : null,
          limit: limitSchema.parse(req.query.limit) ?? 20,
          offset: offsetSchema.parse(req.query.offset) ?? 0,
        }),
      );
    }),
  );

  router.get(
    '/gyms/provider',
    asyncHandler(async (_req, res) => {
      res.json(service.gymProviderStatus());
    }),
  );

  router.get(
    '/gyms/nearby',
    asyncHandler(async (req, res) => {
      res.json(
        await service.nearbyGyms(
          viewer(req),
          z.coerce.number().min(-90).max(90).parse(req.query.lat),
          z.coerce.number().min(-180).max(180).parse(req.query.lng),
          z.coerce.number().int().min(1).max(100).optional().parse(req.query.radius_km),
          limitSchema.parse(req.query.limit) ?? 20,
        ),
      );
    }),
  );

  router.get(
    '/gyms',
    asyncHandler(async (req, res) => {
      res.json(
        await service.searchGyms(viewer(req), {
          query: String(req.query.q ?? ''),
          country: String(req.query.country ?? ''),
          city: String(req.query.city ?? ''),
          area: String(req.query.area ?? ''),
          postalCode: String(req.query.postal_code ?? ''),
          limit: limitSchema.parse(req.query.limit) ?? 20,
          offset: offsetSchema.parse(req.query.offset) ?? 0,
        }),
      );
    }),
  );

  router.get(
    '/gyms/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      res.json(await service.gymDetails(viewer(req), id));
    }),
  );

  router.post(
    '/gyms',
    asyncHandler(async (req, res) => {
      const input = z
        .object({
          name: z.string().trim().min(2).max(90),
          city: z.string().trim().min(2).max(60),
          area: z.string().trim().max(60).nullish(),
          address: z.string().trim().max(160).nullish(),
          state: z.string().trim().max(80).nullish(),
          country: z.string().trim().max(80).nullish(),
          postalCode: z.string().trim().max(24).nullish(),
        })
        .parse(req.body);
      res.status(201).json(await service.requestGym(viewer(req), input));
    }),
  );

  router.post(
    '/gyms/:id/join',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({
          isPrimary: z.boolean().optional(),
          membershipType: z.enum(['member', 'day_pass', 'online', 'coach']).optional(),
          visibility: z.enum(['private', 'members', 'public']).optional(),
        })
        .parse(req.body ?? {});
      await service.joinGym(viewer(req), id, input);
      res.status(204).end();
    }),
  );

  router.post(
    '/gyms/:id/report',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({
          reason: z.enum(['incorrect_details', 'spam', 'inappropriate', 'other']).default('incorrect_details'),
          details: z.string().trim().max(1000).nullish(),
        })
        .parse(req.body ?? {});
      res.status(201).json(
        await service.report(viewer(req), {
          targetType: 'gym',
          targetID: id,
          reason: input.reason,
          details: input.details ?? null,
        }),
      );
    }),
  );

  router.delete(
    '/gyms/membership',
    asyncHandler(async (req, res) => {
      await service.leaveGym(viewer(req));
      res.status(204).end();
    }),
  );

  router.delete(
    '/gyms/membership/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      await service.removeGymMembership(viewer(req), id);
      res.status(204).end();
    }),
  );

  router.put(
    '/area',
    asyncHandler(async (req, res) => {
      const input = z
        .object({ city: z.string().trim().min(2).max(60), area: z.string().trim().min(2).max(60) })
        .parse(req.body);
      await service.setArea(viewer(req), input.city, input.area);
      res.status(204).end();
    }),
  );

  router.put(
    '/profile',
    asyncHandler(async (req, res) => {
      res.json(await service.saveProfile(viewer(req), profileSchema.parse(req.body)));
    }),
  );

  router.post(
    '/profile/avatar',
    express.raw({ type: ['image/jpeg', 'image/png'], limit: '5mb' }),
    asyncHandler(async (req, res) => {
      const body = req.body;
      if (!Buffer.isBuffer(body) || body.length === 0) {
        throw badRequest('invalid_image', 'Send a JPEG or PNG image.');
      }
      const contentType = req.header('content-type') ?? '';
      if (!['image/jpeg', 'image/png'].includes(contentType)) {
        throw badRequest('invalid_image', 'Send a JPEG or PNG image.');
      }
      let url = await service.uploadAvatar(viewer(req), body, contentType);
      if (url.startsWith('/')) url = `${req.protocol}://${req.get('host')}${url}`;
      res.status(201).json({ avatar_url: url });
    }),
  );

  router.put(
    '/preferences',
    asyncHandler(async (req, res) => {
      res.json(await service.savePreferences(viewer(req), preferencesSchema.parse(req.body)));
    }),
  );

  router.post(
    '/connections',
    asyncHandler(async (req, res) => {
      const { target } = z.object({ target: z.string().uuid() }).parse(req.body);
      res.status(201).json(await service.sendConnectionRequest(viewer(req), target));
    }),
  );

  router.post(
    '/connections/:id/respond',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const { accept } = z.object({ accept: z.boolean() }).parse(req.body);
      res.json(await service.respondToConnection(viewer(req), id, accept));
    }),
  );

  router.delete(
    '/connections/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      await service.removeConnection(viewer(req), id);
      res.status(204).end();
    }),
  );

  router.post(
    '/blocks',
    asyncHandler(async (req, res) => {
      const input = z.object({ target: z.string().uuid(), blocked: z.boolean() }).parse(req.body);
      await service.block(viewer(req), input.target, input.blocked);
      res.status(204).end();
    }),
  );

  router.get(
    '/connections',
    asyncHandler(async (req, res) => {
      res.json(await service.connections(viewer(req)));
    }),
  );

  router.get(
    '/blocks',
    asyncHandler(async (req, res) => {
      res.json(await service.blockedMembers(viewer(req)));
    }),
  );

  router.get(
    '/profiles/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const profile = await service.publicProfile(viewer(req), id);
      if (!profile) {
        res.status(404).json({ error: { code: 'not_found', message: 'That profile is not available.' } });
        return;
      }
      res.json(profile);
    }),
  );

  router.get(
    '/feed',
    asyncHandler(async (req, res) => {
      const filter = z.enum(['all', 'connections', 'gym']).catch('all').parse(req.query.filter);
      res.json(
        await service.feed(
          viewer(req),
          filter,
          limitSchema.parse(req.query.limit) ?? 20,
          offsetSchema.parse(req.query.offset) ?? 0,
        ),
      );
    }),
  );

  router.post(
    '/posts',
    asyncHandler(async (req, res) => {
      const input = postSchema.parse(req.body);
      res.status(201).json(
        await service.createPost(viewer(req), {
          id: input.id,
          content: input.content,
          kind: input.kind,
          sessionID: input.sessionId ?? null,
          achievementLabel: input.achievementLabel ?? null,
          session: input.session ?? null,
        }),
      );
    }),
  );

  router.patch(
    '/posts/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const { content } = z.object({ content: z.string().min(1).max(2000) }).parse(req.body);
      await service.updatePost(viewer(req), id, content);
      res.status(204).end();
    }),
  );

  router.delete(
    '/posts/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      await service.deletePost(viewer(req), id);
      res.status(204).end();
    }),
  );

  router.post(
    '/posts/:id/like',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const { liked } = z.object({ liked: z.boolean() }).parse(req.body);
      res.json(await service.toggleLike(viewer(req), id, liked));
    }),
  );

  router.get(
    '/posts/:id/comments',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      res.json(
        await service.comments(
          viewer(req),
          id,
          limitSchema.parse(req.query.limit) ?? 50,
          offsetSchema.parse(req.query.offset) ?? 0,
        ),
      );
    }),
  );

  router.post(
    '/posts/:id/comments',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({ id: z.string().uuid(), content: z.string().min(1).max(1000) })
        .parse(req.body);
      res.status(201).json(
        await service.addComment(viewer(req), { id: input.id, postID: id, content: input.content }),
      );
    }),
  );

  router.delete(
    '/comments/:id',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      await service.deleteComment(viewer(req), id);
      res.status(204).end();
    }),
  );

  router.post(
    '/posts/:id/hide',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const { hidden } = z.object({ hidden: z.boolean() }).parse(req.body);
      await service.hidePost(viewer(req), id, hidden);
      res.status(204).end();
    }),
  );

  router.get(
    '/conversations',
    asyncHandler(async (req, res) => {
      res.json(await service.conversations(viewer(req)));
    }),
  );

  router.get(
    '/conversations/:id/messages',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const before = z.string().datetime({ offset: true }).nullish().parse(req.query.before);
      res.json(
        await service.messages(viewer(req), id, before ?? null, limitSchema.parse(req.query.limit) ?? 40),
      );
    }),
  );

  router.post(
    '/conversations/:id/messages',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({ id: z.string().uuid(), body: z.string().min(1).max(2000) })
        .parse(req.body);
      const result = await service.sendMessage(viewer(req), {
        id: input.id,
        conversationID: id,
        body: input.body,
      });
      res.status(result.duplicate ? 200 : 201).json(result);
    }),
  );

  router.post(
    '/conversations/:id/read',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      await service.markConversationRead(viewer(req), id);
      res.status(204).end();
    }),
  );

  router.post(
    '/conversations/:id/mute',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const { muted } = z.object({ muted: z.boolean() }).parse(req.body);
      await service.muteConversation(viewer(req), id, muted);
      res.status(204).end();
    }),
  );

  router.post(
    '/reports',
    asyncHandler(async (req, res) => {
      const input = z
        .object({
          targetType: z.enum(['profile', 'post', 'comment', 'message']),
          targetId: z.string().uuid(),
          reason: z.enum(['harassment', 'spam', 'inappropriate', 'impersonation', 'suspicious', 'other']),
          details: z.string().trim().max(1000).nullish(),
        })
        .parse(req.body);
      res.status(201).json(
        await service.report(viewer(req), {
          targetType: input.targetType,
          targetID: input.targetId,
          reason: input.reason,
          details: input.details ?? null,
        }),
      );
    }),
  );

  router.get(
    '/notifications',
    asyncHandler(async (req, res) => {
      res.json(
        await service.notifications(
          viewer(req),
          limitSchema.parse(req.query.limit) ?? 30,
          offsetSchema.parse(req.query.offset) ?? 0,
        ),
      );
    }),
  );

  router.post(
    '/notifications/read',
    asyncHandler(async (req, res) => {
      const { ids } = z
        .object({ ids: z.array(z.string().uuid()).max(100).nullish() })
        .parse(req.body ?? {});
      await service.markNotificationsRead(viewer(req), ids ?? null);
      res.status(204).end();
    }),
  );

  router.get(
    '/admin/reports',
    asyncHandler(async (req, res) => {
      res.json(await service.adminReports(viewer(req)));
    }),
  );

  router.post(
    '/admin/users/:id/suspension',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({ suspended: z.boolean(), reason: z.string().trim().max(200).nullish() })
        .parse(req.body);
      await service.adminSetSuspension(viewer(req), id, input.suspended, input.reason ?? null);
      res.status(204).end();
    }),
  );

  router.post(
    '/admin/reports/:id/resolve',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({
          action: z.enum(['remove_content', 'suspend_user', 'dismiss', 'no_action']),
          note: z.string().trim().max(500).nullish(),
        })
        .parse(req.body);
      await service.adminResolveReport(viewer(req), id, input.action, input.note ?? null);
      res.status(204).end();
    }),
  );

  router.get(
    '/admin/gyms',
    asyncHandler(async (req, res) => {
      res.json(await service.adminGyms(viewer(req)));
    }),
  );

  router.post(
    '/admin/gyms/:id/review',
    asyncHandler(async (req, res) => {
      const { id } = idsSchema.parse(req.params);
      const input = z
        .object({ approve: z.boolean(), note: z.string().trim().max(500).nullish() })
        .parse(req.body);
      await service.adminReviewGym(viewer(req), id, input.approve, input.note ?? null);
      res.status(204).end();
    }),
  );

  router.get(
    '/admin/audit',
    asyncHandler(async (req, res) => {
      res.json(await service.adminAudit(viewer(req)));
    }),
  );

  return router;
}
