# Runbook: recrear el esquema JOBPROCESOR en DEV desde cero

Objetivo: dejar en DEV la estructura exacta de PRE, sin residuos de datos
ni de estructura antigua. La carga de datos la hara el equipo de aplicacion.

Contexto: el viernes se lanzo el .sql de DDLs pero las tablas ya existian y
el import las skipeo, dejando estructura/datos viejos. Hay que empezar de 0.

TRUNCATE NO sirve: solo vacia datos, mantiene la estructura antigua.

---

## OPCION A (RECOMENDADA): DROP USER CASCADE + impdp

La mas limpia y rapida. El dump de expdp en modo schemas= ya contiene el
CREATE USER, asi que el impdp recrea el usuario y todos los objetos de una vez.

### 1. Backup de seguridad de grants (red de seguridad, ~10s)
```sql
-- como SYSDBA en DEV, guarda la salida
@backup_grants_antes_drop_JOBPROCESOR.sql
```

### 2. Borrar el usuario completo
```sql
-- como SYSDBA en DEV
DROP USER JOBPROCESOR CASCADE;
```

### 3. Recrear usuario + estructura desde el dump
```bash
impdp \"/ as sysdba\" schemas=JOBPROCESOR content=METADATA_ONLY \
  directory=SCTASH24167274 dumpfile=JOBPROCESOR_ddl.dmp \
  logfile=JOBPROCESOR_ddl_imp.log
```

### 4. Verificar
```sql
SELECT object_type, COUNT(*) FROM dba_objects
WHERE owner = 'JOBPROCESOR' GROUP BY object_type ORDER BY object_type;

SELECT COUNT(*) AS invalidos FROM dba_objects
WHERE owner = 'JOBPROCESOR' AND status = 'INVALID';
```
Si hay invalidos, recompilar:
```sql
EXEC DBMS_UTILITY.COMPILE_SCHEMA('JOBPROCESOR', FALSE);
```

Nota: los grants que JOBPROCESOR recibio sobre objetos de OTROS esquemas no
estan en el dump (ver salida del paso 1). Reponerlos solo si la carga los
necesita; se puede ir resolviendo en los dias siguientes.

---

## OPCION B: mantener el usuario, borrar solo los objetos

Usar si por politica no se puede/quiere borrar el usuario (conserva grants,
quotas y privilegios tal cual estan ahora en DEV).

### 1. Borrar todos los objetos del esquema
```sql
SET SERVEROUTPUT ON SIZE UNLIMITED
@../drop_all_objects_JOBPROCESOR.sql
```

### 2. Generar el SQL para revisar (no ejecuta nada)
```bash
impdp \"/ as sysdba\" schemas=JOBPROCESOR directory=SCTASH24167274 \
  dumpfile=JOBPROCESOR_ddl.dmp logfile=JOBPROCESOR_ddl_sqlfile.log \
  sqlfile=JOBPROCESOR_ddl.sql
```

### 3. Ejecutar el DDL en DEV
```sql
@JOBPROCESOR_ddl.sql
```

### 4. Verificar (igual que Opcion A, paso 4)

---

## Recomendacion

Opcion A. Es un solo flujo, garantiza cero residuos y recrea tambien el
usuario con la configuracion de PRE. El backup del paso 1 cubre cualquier
imprevisto con grants externos.
