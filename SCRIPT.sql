--AUTOR: VICTOR GONZALEZ DEL CAMPO vgd1005@alu.ubu.es
--REPOSITORIO: https://github.com/victoritis/PLSQL.git

-- Eliminación de tablas y secuencias existentes
drop table modelos cascade constraints;
drop table vehiculos cascade constraints;
drop table clientes cascade constraints;
drop table facturas cascade constraints;
drop table lineas_factura cascade constraints;
drop table reservas cascade constraints;

drop sequence seq_modelos;
drop sequence seq_num_fact;
drop sequence seq_reservas;

-- Creación de tablas
create table clientes(
  NIF varchar(9) primary key,
  nombre varchar(20) not null,
  ape1 varchar(20) not null,
  ape2 varchar(20) not null,
  direccion varchar(40)
);

create sequence seq_modelos;

create table modelos(
  id_modelo integer primary key,
  nombre varchar(30) not null,
  precio_cada_dia numeric(6,2) not null check (precio_cada_dia>=0)
);

create table vehiculos(
  matricula varchar(8) primary key,
  id_modelo integer not null references modelos,
  color varchar(10)
);

create sequence seq_reservas;
create table reservas(
  idReserva integer primary key,
  cliente varchar(9) references clientes,
  matricula varchar(8) references vehiculos,
  fecha_ini date not null,
  fecha_fin date,
  check (fecha_fin >= fecha_ini)
);

create sequence seq_num_fact;
create table facturas(
  nroFactura integer primary key,
  importe numeric(8, 2),
  cliente varchar(9) not null references clientes
);

create table lineas_factura(
  nroFactura integer references facturas,
  concepto char(60),
  importe numeric(7, 2),
  primary key (nroFactura, concepto)
);

/*
 * Procedimiento: alquilar_coche
 * Descripción: Este procedimiento gestiona el alquiler de un coche por parte de un cliente.
 *              Verifica que el cliente y el coche existen, que el coche está disponible para las fechas dadas,
 *              calcula el importe del alquiler y genera la correspondiente factura.
 * Argumentos:
 *   - arg_NIF_cliente: NIF del cliente que realiza el alquiler.
 *   - arg_matricula: Matrícula del coche que se desea alquilar.
 *   - arg_fecha_ini: Fecha de inicio del alquiler.
 *   - arg_fecha_fin: Fecha de fin del alquiler.
 * Variables:
 *   - v_precio_dia: Precio por día del modelo del coche.
 *   - v_nombre_modelo: Nombre del modelo del coche.
 *   - v_count: Contador para verificar la disponibilidad del coche.
 *   - v_n_dias: Número de días de alquiler.
 *   - v_importe: Importe total del alquiler.
 *   - v_cliente_count: Contador para verificar la existencia del cliente.
 */
create or replace procedure alquilar_coche(
  arg_NIF_cliente varchar,
  arg_matricula varchar,
  arg_fecha_ini date,
  arg_fecha_fin date
) is
  v_precio_dia modelos.precio_cada_dia%type;
  v_nombre_modelo modelos.nombre%type;
  v_count integer;
  v_n_dias integer;
  v_importe numeric(8, 2);
  v_cliente_count integer;
begin
  -- Comprobar si la fecha de inicio no es posterior a la fecha fin
  if arg_fecha_ini > arg_fecha_fin then
    raise_application_error(-20001, 'No pueden realizarse alquileres por períodos inferiores a 1 día');
end if;

  -- Seleccionar el vehículo y bloquearlo
begin
select m.precio_cada_dia, m.nombre
into v_precio_dia, v_nombre_modelo
from vehiculos v
         join modelos m on v.id_modelo = m.id_modelo
where v.matricula = arg_matricula
    for update of v.matricula;

-- Si no se encuentra el vehículo, lanzar error
exception
      when no_data_found then
        raise_application_error(-20002, 'Vehiculo inexistente.');
end;

  -- Comprobar si ya existe una reserva solapada para el vehículo
select count(*)
into v_count
from reservas
where matricula = arg_matricula
  and (
        (arg_fecha_ini between fecha_ini and fecha_fin) or
        (arg_fecha_fin between fecha_ini and fecha_fin) or
        (fecha_ini between arg_fecha_ini and arg_fecha_fin) or
        (fecha_fin between arg_fecha_ini and arg_fecha_fin)
    );

-- Si el coche ya está reservado para esas fechas, lanzar error
if v_count > 0 then
    raise_application_error(-20003, 'El vehículo no está disponible para esas fechas.');
end if;

  -- Validar la existencia del cliente
select count(*)
into v_cliente_count
from clientes
where NIF = arg_NIF_cliente;

-- Si el cliente no existe, lanzar error
if v_cliente_count = 0 then
    raise_application_error(-20004, 'Cliente inexistente.');
end if;

  -- Insertar la reserva
insert into reservas(idReserva, cliente, matricula, fecha_ini, fecha_fin)
values (seq_reservas.nextval, arg_NIF_cliente, arg_matricula, arg_fecha_ini, arg_fecha_fin);

-- Calcular el número de días y el importe
v_n_dias := arg_fecha_fin - arg_fecha_ini;
  v_importe := v_n_dias * v_precio_dia;

  -- Crear la factura
insert into facturas(nroFactura, importe, cliente)
values (seq_num_fact.nextval, v_importe, arg_NIF_cliente);

-- Crear la línea de factura
insert into lineas_factura(nroFactura, concepto, importe)
values (seq_num_fact.currval, v_n_dias || ' días de alquiler vehículo modelo ' || v_nombre_modelo, v_importe);

end;
/


-- P6a: ¿Por qué crees que se hace la recomendación del paso 2?
-- La recomendación del paso 2 es súper importante para asegurarnos de que estamos trabajando con los datos correctos y que estamos bloqueando el coche adecuado. Necesitamos bloquear el coche que se va a alquilar para que otros procesos no puedan hacer operaciones sobre el mismo coche al mismo tiempo. Esto evita problemas de concurrencia y asegura que el coche esté disponible para el cliente que hace la reserva.
-- Sin esta medida, podríamos tener situaciones donde varios clientes intentan reservar el mismo coche al mismo tiempo, lo que causaría conflictos y datos corruptos. Por eso, esta recomendación es una práctica estándar para manejar la concurrencia y mantener la integridad de los datos en bases de datos.

-- P6b: El resultado de la SELECT del paso 4, ¿sigue siendo fiable en el paso 5?, ¿por qué?
-- Sí, el resultado de la SELECT del paso 4 sigue siendo fiable en el paso 5. Esto es porque desde el paso 2, la transacción ha bloqueado el registro del coche con la cláusula FOR UPDATE. Este bloqueo asegura que ningún otro proceso pueda cambiar el estado del coche mientras la transacción actual está en curso.
-- En términos de concurrencia, el bloqueo del paso 2 asegura que el estado del coche y cualquier reserva existente no puedan ser modificados por otras transacciones hasta que la transacción actual termine. Así, cuando llegamos al paso 5, podemos estar seguros de que los datos son coherentes y no han sido cambiados por otras operaciones concurrentes.

-- P6c: En este paso, la ejecución concurrente del mismo procedimiento ALQUILA con, quizás otros o los mismos argumentos, ¿podría habernos añadido una reserva no recogida en esa SELECT que fuese incompatible con nuestra reserva?, ¿por qué?
-- No, la ejecución concurrente del mismo procedimiento ALQUILA no podría añadir una reserva no recogida en esa SELECT por el bloqueo aplicado con FOR UPDATE. Cuando un registro es bloqueado por una transacción, ninguna otra transacción puede modificarlo hasta que se libere el bloqueo (es decir, hasta que la transacción se complete o se deshaga).
-- Esto significa que cualquier intento de reservar el mismo coche por otra transacción sería bloqueado y tendría que esperar a que la transacción actual se termine. Este mecanismo de bloqueo asegura que no se añadan reservas solapadas mientras estamos haciendo nuestras operaciones.

-- P6d: ¿Qué tipo de estrategia de programación has empleado en tu código? ¿Cómo se refleja esto en tu código?
-- He utilizado una estrategia de programación defensiva. Esto significa anticipar problemas y errores antes de que ocurran y asegurarse de que el sistema puede manejarlos adecuadamente sin fallar. En este procedimiento, esto se refleja en varias prácticas clave.
-- Primero, hay múltiples verificaciones de condiciones antes de realizar operaciones críticas. Por ejemplo, se valida que la fecha de inicio no sea posterior a la fecha de fin antes de seguir. Esta validación temprana evita que se hagan operaciones inválidas.
-- Segundo, se usa el manejo de excepciones para capturar y manejar errores específicos, como cuando no se encuentra un coche o un cliente, o cuando hay reservas solapadas. Al capturar estas excepciones y proporcionar mensajes de error claros, se evita que el sistema falle inesperadamente y se da información útil para corregir el problema.
-- Tercero, se emplean bloqueos (FOR UPDATE) para asegurar la integridad de los datos durante la transacción, evitando condiciones de carrera y garantizando que los datos se mantengan consistentes incluso en entornos concurrentes.
-- Esta estrategia defensiva asegura que el sistema sea robusto y fiable, anticipando y manejando errores de manera controlada, lo que facilita el mantenimiento y mejora la experiencia del usuario.


-- Procedimiento para resetear secuencias
--From https://stackoverflow.com/questions/51470/how-do-i-reset-a-sequence-in-oracle
create or replace procedure reset_seq(p_seq_name varchar) is
  l_val number;
begin
  execute immediate 'select ' || p_seq_name || '.nextval from dual' INTO l_val;
  execute immediate 'alter sequence ' || p_seq_name || ' increment by -' || l_val || ' minvalue 0';
  execute immediate 'select ' || p_seq_name || '.nextval from dual' INTO l_val;
  execute immediate 'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';
end;
/

-- Procedimiento para inicializar datos de prueba
create or replace procedure inicializa_test is
begin
  reset_seq('seq_modelos');
  reset_seq('seq_num_fact');
  reset_seq('seq_reservas');
  
  delete from lineas_factura;
  delete from facturas;
  delete from reservas;
  delete from vehiculos;
  delete from modelos;
  delete from clientes;
  
  insert into clientes values ('12345678A', 'Pepe', 'Perez', 'Porras', 'C/Perezoso n1');
  insert into clientes values ('11111111B', 'Beatriz', 'Barbosa', 'Bernardez', 'C/Barriocanal n1');
  
  insert into modelos values (seq_modelos.nextval, 'Renault Clio Gasolina', 15);
  insert into vehiculos values ('1234-ABC', seq_modelos.currval, 'VERDE');

  insert into modelos values (seq_modelos.nextval, 'Renault Clio Gasoil', 16);
  insert into vehiculos values ('1111-ABC', seq_modelos.currval, 'VERDE');
  insert into vehiculos values ('2222-ABC', seq_modelos.currval, 'GRIS');
  
  commit;
end;
/

-- Ejecución del procedimiento de inicialización
exec inicializa_test;

-- Procedimiento de pruebas
create or replace procedure test_alquila_coches is
begin
  -- Caso 1: Todo correcto
  -- Este test verifica que el procedimiento realiza correctamente la reserva y crea la factura correspondiente cuando todos los valores son correctos.
  begin
    inicializa_test;
    begin
      -- Intentar realizar una reserva con valores correctos
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
      dbms_output.put_line('Caso 1: Reserva realizada correctamente');
    exception
      when others then
        dbms_output.put_line('Caso 1: Error inesperado - ' || sqlerrm);
    end;
  end;

  -- Caso 2: Número de días negativo
  -- Este test verifica que el procedimiento arroja un error cuando la fecha de inicio es posterior a la fecha de fin.
  begin
    inicializa_test;
    begin
      -- Intentar alquilar un coche con una fecha de fin anterior a la fecha de inicio
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-09', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20001 then
          dbms_output.put_line('Caso 2: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 2: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- Caso 3: Vehículo inexistente
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un vehículo que no existe en la base de datos.
  begin
    inicializa_test;
    begin
      -- Intentar alquilar un coche con una matrícula que no existe
      alquilar_coche('12345678A', '9999-XYZ', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20002 then
          dbms_output.put_line('Caso 3: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 3: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- Caso 4: Intentar alquilar un coche ya alquilado
  -- 4.1: La fecha de inicio del alquiler está dentro de una reserva
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche en una fecha de inicio que se solapa con una reserva existente.
  begin
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-14', 'YYYY-MM-DD'), to_date('2024-06-16', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('Caso 4.1: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 4.1: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- 4.2: La fecha de fin del alquiler está dentro de una reserva
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche en una fecha de fin que se solapa con una reserva existente.
  begin
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-09', 'YYYY-MM-DD'), to_date('2024-06-11', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('Caso 4.2: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 4.2: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- 4.3: El intervalo del alquiler está dentro de una reserva
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche en un intervalo de fechas que está completamente dentro de una reserva existente.
  begin
    inicializa_test;
    begin
      -- Crear una reserva inicial
      alquilar_coche('12345678A', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-15', 'YYYY-MM-DD'));
      -- Intentar crear una reserva solapada
      alquilar_coche('11111111B', '1234-ABC', to_date('2024-06-11', 'YYYY-MM-DD'), to_date('2024-06-14', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20003 then
          dbms_output.put_line('Caso 4.3: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 4.3: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;

  -- Caso 5: Cliente inexistente
  -- Este test verifica que el procedimiento arroja un error cuando se intenta alquilar un coche para un cliente que no existe en la base de datos.
  begin
    inicializa_test;
    begin
      -- Intentar alquilar un coche con un NIF de cliente que no existe
      alquilar_coche('99999999Z', '1234-ABC', to_date('2024-06-10', 'YYYY-MM-DD'), to_date('2024-06-12', 'YYYY-MM-DD'));
    exception
      when others then
        if sqlcode = -20004 then
          dbms_output.put_line('Caso 5: Correcto - ' || sqlerrm);
        else
          dbms_output.put_line('Caso 5: Incorrecto - ' || sqlerrm);
        end if;
    end;
  end;


end;
/

set serveroutput on
exec test_alquila_coches;

