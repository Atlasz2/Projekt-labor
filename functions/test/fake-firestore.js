// Minimális in-memory Firestore-stub a redeem-core tesztjeihez.
// Csak azt a felületet valósítja meg, amit a core használ:
// collection/doc get-set-update, where('==')+limit+get, runTransaction, batch,
// valamint a FieldValue transzformok (serverTimestamp, increment, arrayUnion).

const SERVER_TIMESTAMP = Symbol('serverTimestamp');

class Increment {
  constructor(n) {
    this.n = n;
  }
}

class ArrayUnion {
  constructor(values) {
    this.values = values;
  }
}

export const FakeFieldValue = {
  serverTimestamp: () => SERVER_TIMESTAMP,
  increment: (n) => new Increment(n),
  arrayUnion: (...values) => new ArrayUnion(values),
};

function applyTransforms(existing, incoming) {
  const out = { ...existing };
  for (const [key, value] of Object.entries(incoming)) {
    if (value === SERVER_TIMESTAMP) {
      out[key] = new Date();
    } else if (value instanceof Increment) {
      out[key] = (Number(out[key]) || 0) + value.n;
    } else if (value instanceof ArrayUnion) {
      const current = Array.isArray(out[key]) ? [...out[key]] : [];
      for (const v of value.values) {
        if (!current.includes(v)) current.push(v);
      }
      out[key] = current;
    } else {
      out[key] = value;
    }
  }
  return out;
}

class FakeDocSnapshot {
  constructor(id, data) {
    this.id = id;
    this._data = data;
  }

  get exists() {
    return this._data !== undefined;
  }

  data() {
    return this._data === undefined ? undefined : { ...this._data };
  }
}

class FakeDocRef {
  constructor(store, path) {
    this.store = store;
    this.path = path;
  }

  get id() {
    return this.path.split('/').at(-1);
  }

  collection(name) {
    return new FakeCollectionRef(this.store, `${this.path}/${name}`);
  }

  async get() {
    return new FakeDocSnapshot(this.id, this.store.data.get(this.path));
  }

  async set(data, options = {}) {
    const existing = this.store.data.get(this.path);
    const base = options.merge && existing ? existing : {};
    this.store.data.set(this.path, applyTransforms(base, data));
  }

  async update(data) {
    const existing = this.store.data.get(this.path);
    if (existing === undefined) {
      throw new Error(`update on missing doc: ${this.path}`);
    }
    this.store.data.set(this.path, applyTransforms(existing, data));
  }
}

class FakeQuery {
  constructor(store, path, filters, limitN) {
    this.store = store;
    this.path = path;
    this.filters = filters;
    this.limitN = limitN;
  }

  where(field, op, value) {
    if (op !== '==') throw new Error(`unsupported operator: ${op}`);
    return new FakeQuery(this.store, this.path, [...this.filters, { field, value }], this.limitN);
  }

  limit(n) {
    return new FakeQuery(this.store, this.path, this.filters, n);
  }

  async get() {
    const prefix = `${this.path}/`;
    const docs = [];
    for (const [path, data] of this.store.data.entries()) {
      if (!path.startsWith(prefix)) continue;
      // Csak közvetlen gyerek dokumentumok (alkollekciók kizárva).
      if (path.slice(prefix.length).includes('/')) continue;
      if (this.filters.every((f) => data[f.field] === f.value)) {
        docs.push(new FakeDocSnapshot(path.slice(prefix.length), data));
      }
      if (this.limitN !== undefined && docs.length >= this.limitN) break;
    }
    return { docs, empty: docs.length === 0 };
  }
}

class FakeCollectionRef extends FakeQuery {
  constructor(store, path) {
    super(store, path, [], undefined);
  }

  doc(id) {
    return new FakeDocRef(this.store, `${this.path}/${id}`);
  }
}

class FakeTransaction {
  constructor(store) {
    this.store = store;
  }

  async get(ref) {
    return ref.get();
  }

  set(ref, data, options) {
    ref.set(data, options);
  }

  update(ref, data) {
    ref.update(data);
  }
}

class FakeBatch {
  constructor() {
    this.ops = [];
  }

  set(ref, data, options) {
    this.ops.push(() => ref.set(data, options));
  }

  update(ref, data) {
    this.ops.push(() => ref.update(data));
  }

  async commit() {
    for (const op of this.ops) await op();
  }
}

export class FakeFirestore {
  constructor() {
    this.data = new Map();
  }

  collection(name) {
    return new FakeCollectionRef(this, name);
  }

  async runTransaction(fn) {
    return fn(new FakeTransaction(this));
  }

  batch() {
    return new FakeBatch();
  }

  /** Teszt-segéd: dokumentum közvetlen beszúrása útvonal alapján. */
  seed(path, data) {
    this.data.set(path, { ...data });
  }

  /** Teszt-segéd: dokumentum kiolvasása útvonal alapján. */
  read(path) {
    return this.data.get(path);
  }
}
