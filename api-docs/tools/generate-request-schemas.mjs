// Writes schemas/requests.yaml: the API's request schemas converted from the Zod schemas of @revamp/validation, so the
// specification and the API's validation cannot drift apart.
//
//   npm i --prefix <tools dir> zod-to-json-schema@3.23.5 js-yaml@4
//   npm run build:packages            # in Revamp-dev
//   node tools/generate-request-schemas.mjs ../../Revamp-dev/packages/validation/dist/index.js schemas/requests.yaml
//
// Objects that are `.strict()` in Zod get `additionalProperties: false` (the API answers 400 to an unknown field); the
// others accept unknown fields and drop them, so no `additionalProperties` is written for them.
import { createRequire } from 'node:module';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const [, , distPath, outPath] = process.argv;
if (!distPath || !outPath) {
  console.error('usage: node generate-request-schemas.mjs <validation dist/index.js> <out.yaml>');
  process.exit(1);
}
const require = createRequire(import.meta.url);
const { zodToJsonSchema } = require('zod-to-json-schema');
const yaml = require('js-yaml');
const validation = await import(resolve(distPath));

const NAMES = [
  'RegisterSchema', 'LoginSchema', 'CreateInvitationSchema', 'JoinInvitationSchema', 'ChangeMemberRoleSchema',
  'CreateLeadSchema', 'GetLeadsQuerySchema', 'TriggerAuditSchema', 'GenerateMvpSchema', 'EditMvpSchema',
  'UpdateMvpTokensSchema', 'MvpVersionParamsSchema', 'ApproveOutreachSchema', 'RejectOutreachSchema',
  'TestEmailOutreachSchema', 'StartDiscoverySchema', 'ImportDiscoverySchema', 'ReverseGeocodeQuerySchema',
  'MvpTrackEventSchema', 'StudioSenderSchema', 'CreatePlatformAuditSchema', 'CreateLotSchema', 'OpenLotSchema',
  'AdminLotsQuerySchema',
];

const dropOpenObjects = (node) => {
  if (Array.isArray(node)) return node.forEach(dropOpenObjects);
  if (node && typeof node === 'object') {
    if (node.additionalProperties === true) delete node.additionalProperties;
    Object.values(node).forEach(dropOpenObjects);
  }
};

const out = {};
for (const name of NAMES) {
  const schema = zodToJsonSchema(validation[name], {
    target: 'openApi3',
    $refStrategy: 'none',
    effectStrategy: 'input',
    removeAdditionalStrategy: 'strict',
  });
  delete schema.$schema;
  dropOpenObjects(schema);
  out[name.replace(/Schema$/, '')] = schema;
}

writeFileSync(
  outPath,
  '# Generated from the Zod schemas of @revamp/validation by tools/generate-request-schemas.mjs; do not edit by hand\n' +
    yaml.dump(out, { noRefs: true, lineWidth: 120 }),
);
console.log(`${Object.keys(out).length} request schemas written to ${outPath}`);
