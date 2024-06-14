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
  concepto char(40),
  importe numeric(7, 2),
  primary key (nroFactura, concepto)
);

-- Procedimiento para alquilar un coche
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

  if v_count > 0 then
    raise_application_error(-20003, 'El vehículo no está disponible para esas fechas.');
  end if;

  -- Insertar la reserva
  begin
    insert into reservas(idReserva, cliente, matricula, fecha_ini, fecha_fin)
    values (seq_reservas.nextval, arg_NIF_cliente, arg_matricula, arg_fecha_ini, arg_fecha_fin);

    -- Si el cliente no existe, lanzar error
    exception
      when no_data_found then
        raise_application_error(-20004, 'Cliente inexistente.');
  end;

  -- Calcular el número de días y el importe
  v_n_dias := arg_fecha_fin - arg_fecha_ini;
  v_importe := v_n_dias * v_precio_dia;

  -- Crear la factura
  insert into facturas(nroFactura, importe, cliente)
  values (seq_num_fact.nextval, v_importe, arg_NIF_cliente);

  -- Crear la línea de factura
  insert into lineas_factura(nroFactura, concepto, importe)
  values (seq_num_fact.currval, v_n_dias || ' días de alquiler vehículo modelo ' || v_nombre_modelo, v_importe);

  -- Aquí irán los siguientes pasos
end;
/



-- Procedimiento para resetear secuencias
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
  -- Caso 1: Número de días negativo
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
  
  -- Caso 2: Vehículo inexistente
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
  
  -- Caso 3: Cliente inexistente
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
  
  -- Caso 4: Intentar alquilar un coche ya alquilado
  -- 4.1: La fecha de inicio del alquiler está dentro de una reserva
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
  
  -- 4.2: La fecha de fin del alquiler está dentro de una reserva
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
  
  -- 4.3: El intervalo del alquiler está dentro de una reserva
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
  
  -- Caso 5: Todo correcto
  declare
  begin
    inicializa_test;
    -- Implementa aquí tu test
  end;
end;
/

set serveroutput on
exec test_alquila_coches;
