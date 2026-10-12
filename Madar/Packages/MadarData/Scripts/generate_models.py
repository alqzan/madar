#!/usr/bin/env python3
"""Regenerate models and schema from the approved dictionary. Does not change the specification."""
import json, pathlib
base = pathlib.Path(__file__).resolve().parents[1]
spec = base.parents[1] / 'Specification' / 'data-dictionary.json'
p = json.loads(spec.read_text())
for f in ['data-dictionary.json', 'settings-schema.json']:
    (base / 'Sources/MadarData/Resources' / f).write_bytes((spec.parent / f).read_bytes())
def default(f):
 t=f['type'];d=f.get('default')
 if t.endswith('?'):return 'nil'
 if d in ['UUID()','Date()','Data()']:return d
 if d is None: return '[]' if t.startswith('[') else {'String':'""','Bool':'false','Double':'0','Int':'0','Data':'Data()','Date':'Date()','UUID':'UUID()'}.get(t,'nil')
 return json.dumps(d,ensure_ascii=False)
code=['import Foundation','import SwiftData','// Generated from Specification/data-dictionary.json v3. UUID foreign keys intentionally avoid ownership relationships.','@MainActor public protocol MadarRecordModel: PersistentModel { var id: UUID { get set }; func record() throws -> DataRecord; func apply(_ record: DataRecord) throws }']
for m in p['models']:
 fs=p['commonFields']+m['fields'];name=m['name']
 code += ['@Model public final class '+name+' {']
 for f in fs:
  code += [('    @Attribute(.externalStorage) ' if name=='Media' and f['name']=='data' else '    ')+f'public var {f["name"]}: {f["type"]} = {default(f)}']
 code += ['    public init() {}','}',f'extension {name}: MadarRecordModel {{','    public func record() throws -> DataRecord {',f'        try DataRecord(model: "{name}", fields: [']
 code += [f'            "{f["name"]}": JSONValue.encode({f["name"]}),' for f in fs]
 code += ['        ])','    }','    public func apply(_ record: DataRecord) throws {']
 code += [f'        {f["name"]} = try record.decode("{f["name"]}", as: {f["type"]}.self)' for f in fs]
 code += ['    }','}']
(base/'Sources/MadarData/GeneratedModels.swift').write_text('\n'.join(code)+'\n')
code=['import Foundation','import SwiftData','public enum MadarSchema: VersionedSchema {', '    public static let versionIdentifier = Schema.Version(3, 0, 0)', '    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }','    public static let version = 3','    public static let syncedTypes: [any PersistentModel.Type] = ['+', '.join(m['name']+'.self' for m in p['models'] if m['config']=='synced')+']','    public static let deviceTypes: [any PersistentModel.Type] = ['+', '.join(m['name']+'.self' for m in p['models'] if m['config']=='deviceOnly')+']','    public static let syncedNames: [String] = '+json.dumps([m['name'] for m in p['models'] if m['config']=='synced']),'    public static var schema: Schema { Schema(versionedSchema: Self.self) }','}','@MainActor public enum RecordBridge {','    public static func all(_ context: ModelContext, syncedOnly: Bool = true) throws -> [DataRecord] {','        var rows: [DataRecord] = []']
for m in p['models']:
 line=f'rows += try context.fetch(FetchDescriptor<{m["name"]}>()).map {{ try $0.record() }}'
 code += [('        '+line) if m['config']=='synced' else '        if !syncedOnly { '+line+' }']
code += ['        return rows','    }','    public static func upsert(_ record: DataRecord, in context: ModelContext) throws {','        switch record.model {']
for m in p['models']:
 name=m['name'];code += [f'        case "{name}":',f'            let rows = try context.fetch(FetchDescriptor<{name}>())',f'            let row = rows.first {{ $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string }} ?? {name}()', '            if row.modelContext == nil { context.insert(row) }','            try row.apply(record)']
code += ['        default: throw DataError.unknownModel(record.model)','        }','    }','}']
(base/'Sources/MadarData/GeneratedSchema.swift').write_text('\n'.join(code)+'\n')

text = (base/'Sources/MadarData/GeneratedSchema.swift').read_text()
instance_lines = ['    public static func instances(_ context: ModelContext) throws -> [any MadarRecordModel] {', '        var result: [any MadarRecordModel] = []']
for model in p['models']:
    if model['config'] == 'synced': instance_lines.append('        result += try context.fetch(FetchDescriptor<' + model['name'] + '>())')
instance_lines += ['        return result', '    }']
text = text.replace('    public static func upsert(', '\n'.join(instance_lines) + '\n    public static func upsert(')
(base/'Sources/MadarData/GeneratedSchema.swift').write_text(text)

text = (base/'Sources/MadarData/GeneratedSchema.swift').read_text()
insert_lines = ['    public static func insert(_ record: DataRecord, in context: ModelContext) throws {', '        switch record.model {']
for model in p['models']:
    insert_lines += ['        case "' + model['name'] + '":', '            let row = ' + model['name'] + '(); context.insert(row); try row.apply(record)']
insert_lines += ['        default: throw DataError.unknownModel(record.model)', '        }', '    }']
text = text.replace('    public static func upsert(', '\n'.join(insert_lines) + '\n    public static func upsert(')
device_lines = ['    public static func deviceRecords(_ context: ModelContext) throws -> [DataRecord] {', '        var rows: [DataRecord] = []']
for model in p['models']:
    if model['config'] == 'deviceOnly': device_lines.append('        rows += try context.fetch(FetchDescriptor<' + model['name'] + '>()).map { try $0.record() }')
device_lines += ['        return rows', '    }']
text = text.replace('    public static func instances(', '\n'.join(device_lines) + '\n    public static func instances(')
(base/'Sources/MadarData/GeneratedSchema.swift').write_text(text)
