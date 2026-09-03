import { describe, it, expect } from 'vitest';
import {
  DEFAULT_PROJECT_ID,
  docProjectId,
  filterByProject,
  slugifyProjectId,
} from './projects';

describe('docProjectId', () => {
  it('hiányzó projectId az alapértelmezettet adja', () => {
    expect(docProjectId({})).toBe(DEFAULT_PROJECT_ID);
    expect(docProjectId({ projectId: '' })).toBe(DEFAULT_PROJECT_ID);
    expect(docProjectId({ projectId: '   ' })).toBe(DEFAULT_PROJECT_ID);
    expect(docProjectId(null)).toBe(DEFAULT_PROJECT_ID);
  });

  it('beállított projectId-t visszaadja', () => {
    expect(docProjectId({ projectId: 'tapolca' })).toBe('tapolca');
  });
});

describe('filterByProject', () => {
  const docs = [
    { id: 'a', projectId: 'nagyvazsony' },
    { id: 'b' }, // hiányzó -> alapértelmezett (nagyvazsony)
    { id: 'c', projectId: 'tapolca' },
    { id: 'd', projectId: '' }, // üres -> alapértelmezett
  ];

  it('az alapértelmezett projektbe a hiányzó/üres is beleszámít', () => {
    const res = filterByProject(docs, 'nagyvazsony').map((d) => d.id);
    expect(res).toEqual(['a', 'b', 'd']);
  });

  it('másik projekt csak a saját dokumentumait adja', () => {
    const res = filterByProject(docs, 'tapolca').map((d) => d.id);
    expect(res).toEqual(['c']);
  });

  it('üres/undefined projectId az alapértelmezettre szűr', () => {
    expect(filterByProject(docs).map((d) => d.id)).toEqual(['a', 'b', 'd']);
  });
});

describe('slugifyProjectId', () => {
  it('ékezetet, kis-nagybetűt, szóközt kezel', () => {
    expect(slugifyProjectId('Nagyvázsony')).toBe('nagyvazsony');
    expect(slugifyProjectId('Új Város')).toBe('uj-varos');
    expect(slugifyProjectId('  Tapolca  ')).toBe('tapolca');
  });

  it('speciális karaktereket kötőjellé alakít és levágja a széleket', () => {
    expect(slugifyProjectId('Balaton-felvidék!!!')).toBe('balaton-felvidek');
  });
});
