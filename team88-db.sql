-- Clean up
DROP TABLE Airline CASCADE CONSTRAINTS;
DROP TABLE Plane CASCADE CONSTRAINTS;
DROP TABLE Flight CASCADE CONSTRAINTS;
DROP TABLE Price CASCADE CONSTRAINTS;
DROP TABLE Customer CASCADE CONSTRAINTS;
DROP TABLE Reservation CASCADE CONSTRAINTS;
DROP TABLE Reservation_detail CASCADE CONSTRAINTS;
DROP TABLE System_time CASCADE CONSTRAINTS;

-- Create Tables
create table Airline(
	airline_id varchar(5),
	airline_name varchar(50),
	airline_abbreviation varchar(10),
	year_founded int,
	CONSTRAINT Airline_PK
		PRIMARY KEY (airline_id) DEFERRABLE
);

create table Plane(
	plane_type char(4),
	manufacture varchar(10),
	plane_capacity int,
	last_service date,
	year int,
	owner_id varchar(5),
	CONSTRAINT Plane_PK
		PRIMARY KEY (plane_type, owner_id) DEFERRABLE,
	CONSTRAINT Plane_to_Airline_FK
		FOREIGN KEY (owner_id) REFERENCES Airline(airline_id) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE
);

create table Flight(
	flight_number varchar(3),
	airline_id varchar(5),
	plane_type char(4),
	departure_city varchar(3),
	arrival_city varchar(3),
	departure_time varchar(4),
	arrival_time varchar(4),
	weekly_schedule varchar(7),
	CONSTRAINT Flight_PK
		PRIMARY KEY (flight_number) DEFERRABLE,
	CONSTRAINT Flight_to_Plane_FK
		FOREIGN KEY (plane_type, airline_id) REFERENCES PLANE(plane_type, owner_id) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE,
	CONSTRAINT Flight_to_Airline_FK
		FOREIGN KEY (airline_id) REFERENCES Airline(airline_id) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE
);

create table Price(
	departure_city varchar(3),
	arrival_city varchar(3),
	airline_id varchar(5),
	high_price int,
	low_price int,
	CONSTRAINT Price_PK
		PRIMARY KEY (departure_city, arrival_city) DEFERRABLE,
	CONSTRAINT Price_to_Airline_FK
		FOREIGN KEY (airline_id) REFERENCES Airline(airline_id) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE
);

create table Customer(
	cid varchar(9),
	salutation varchar(3),
	first_name varchar(30),
	last_name varchar(30),
	credit_card_num varchar(16),
	credit_card_expire date,
	street varchar(30),
	city varchar(30),
	state varchar(2),
	phone varchar(10),
	email varchar(30),
	frequent_miles varchar(5),
	CONSTRAINT Customer_PK 
		PRIMARY KEY (cid) DEFERRABLE,
	CONSTRAINT Customer_to_Airline_FK
		FOREIGN KEY (frequent_miles) REFERENCES Airline(airline_id) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE
);

create table Reservation(
	reservation_number varchar(5),
	cid varchar(9),
	cost int,
	credit_card_num varchar(16),
	reservation_date date,
	ticketed varchar(1),
	start_city varchar(3),
	end_city varchar(3),
	CONSTRAINT Reservation_PK 
		PRIMARY KEY (reservation_number) DEFERRABLE,
	CONSTRAINT Reservation_FK 
		FOREIGN KEY (cid) REFERENCES Customer(cid) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE
);

create table Reservation_detail(
	reservation_number varchar(5),
	flight_number varchar(3),
	flight_date date,
	leg int,
	CONSTRAINT R_detail_PK 
		PRIMARY KEY (reservation_number, leg) DEFERRABLE,
	CONSTRAINT R_detail_to_Reservation_FK1 
		FOREIGN KEY (reservation_number) REFERENCES Reservation(reservation_number) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE,
	CONSTRAINT R_detail_to_Flight_FK2 
		FOREIGN KEY (flight_number) REFERENCES Flight(flight_number) ON DELETE CASCADE INITIALLY DEFERRED DEFERRABLE
);

create table System_time(
	c_date date,
	CONSTRAINT Date_PK 
		PRIMARY KEY (c_date) DEFERRABLE
);        

-- VIEWS
--compiles necessary information about the reservation
create or replace view seatingInfo
	as select Reservation_detail.reservation_number, Reservation_detail.flight_number, Reservation_detail.flight_date, Flight.airline_id, Flight.plane_type, Plane.plane_capacity, Reservation.ticketed
	from Reservation_detail, Flight, Plane, Reservation
	where Reservation_detail.reservation_number = Reservation.reservation_number 
	and Reservation_detail.flight_number = Flight.flight_number 
	and Flight.plane_type = Plane.plane_type
	and Reservation.ticketed = 'Y';

--gets the number of ticketed reservations for each plane
create or replace view seatsReserved(flight_number, seat_count)
	as select flight_number, count(flight_number)
	from seatingInfo, System_time
	where ((flight_date - c_date) * 24) <= 12 
	group by flight_number;

--creates a list of reservations, flight numbers and flight dates
create or replace view allReservations
	as SELECT salutation, first_name, last_name, Reservation_detail.flight_number, flight_date 
	   FROM Customer, Reservation, Reservation_detail 
	   WHERE Reservation.cid = Customer.cid 
	   AND Reservation_detail.reservation_number = Reservation.reservation_number;
-- FUNCTIONS
CREATE OR REPLACE FUNCTION get_plane_capacity (flightNum in varchar) RETURN int
AS
capacity float;
BEGIN
	-- Get the capacity of that plane
	SELECT plane_capacity into capacity
	FROM Plane
	WHERE plane_type = (-- Get the plane type
						SELECT plane_type
						FROM Flight
						WHERE flight_number = flightNum
						);

	return (capacity);
END;
/

CREATE OR REPLACE FUNCTION get_num_flight_reservations (flightNum in varchar) RETURN int
AS
number_of_reservations int;
BEGIN
	-- Get the number of reservations for this flight
	SELECT COUNT(*) into number_of_reservations
	FROM Flight
	WHERE flight_number = flightNum;

	return (number_of_reservations);
END;
/

CREATE OR REPLACE FUNCTION get_new_plane (cap in int) RETURN char
AS
p_type char;
BEGIN
	-- Select the plane with the next highest capacity
	SELECT plane_type into p_type
	FROM (SELECT *
			FROM Plane
			WHERE plane_capacity > cap
			ORDER BY plane_capacity ASC)
	WHERE ROWNUM = 1;
	
	return (p_type);
END;
/

--finds a new plane to accomadate a smaller group of reservations
CREATE OR REPLACE FUNCTION downsize_plane (cap in int) RETURN char
AS
p_type char;
BEGIN
	-- Select the plane with the next highest capacity
	SELECT plane_type into p_type
	FROM (SELECT *
			FROM Plane
			WHERE plane_capacity > cap
			ORDER BY plane_capacity DESC)
	WHERE ROWNUM = 1;
	
	return (p_type);
END;
/

-- TRIGGERS
--1)
create or replace trigger adjustTicket
before update of leg on Reservation_detail
referencing new as newVal old as oldVal
for each row
declare 
 old_high_price int;
 upd_high_price int;
 old_low_price int;
 upd_low_price int;
begin
--get the high price of the old leg
 Select high_price into old_high_price 
 From Price Join Flight on Flight.airline_id = Price.airline_id 
 Where flight_number = :oldVal.flight_number;

 --get the low price of the old leg
 Select low_price into old_low_price 
 From Price Join Flight on Flight.airline_id = Price.airline_id 
 Where flight_number = :oldVal.flight_number;

--get the high price of the new leg
 Select high_price into upd_high_price 
 From Price Join Flight on Flight.airline_id = Price.airline_id 
 Where flight_number = :newVal.flight_number;

 --get the low price of the new leg
 Select low_price into upd_low_price 
 From Price Join Flight on Flight.airline_id = Price.airline_id 
 Where flight_number = :newVal.flight_number;

 --adjust the cost of the high price if necessary
 IF old_high_price != upd_high_price THEN
 	update Reservation 
 	set cost = cost - old_high_price + upd_high_price 
 	where ticketed = 'N' and :oldVal.reservation_number = Reservation.reservation_number;
 END IF;

   --sadjust the cost of the low price if necessary
 IF old_low_price != upd_low_price THEN
 	update Reservation 
 	set cost = cost - old_low_price + upd_low_price 
 	where ticketed = 'N' and :oldVal.reservation_number = Reservation.reservation_number;
 END IF;

end;
/

--2)
CREATE OR REPLACE TRIGGER planeUpgrade
AFTER INSERT ON Reservation_detail
FOR EACH ROW
BEGIN
	-- If the number of reservations on the flight is equal to the plane's capacity
	IF get_num_flight_reservations(:new.flight_number) >= get_plane_capacity(:new.flight_number) THEN
		-- Find a new plane
		UPDATE Flight
		SET plane_type = get_new_plane(get_num_flight_reservations(:new.flight_number))
		WHERE flight_number = :new.flight_number;
	END IF;		
END;
/

--3)
create or replace trigger cancelReservation 
before update of c_date on System_time
referencing new as newVal old as oldVal
for each row
Declare
	seats_used int;
	seats_total int;
Begin
 --deletes all the reservations 12 hours from the flight 
 Delete From Reservation
 Where Exists ( Select *
 				From Reservation_detail Join Reservation On Reservation_detail.reservation_number = Reservation.reservation_number
 				Where ((flight_date - :newVal.c_date) * 24) <= 12 				
 				And Reservation.ticketed = 'N');

--downsizes the plane if there is a smaller accomodation
 Select seat_count Into seats_used 
 From seatsReserved, seatingInfo 
 Where seatsReserved.flight_number = seatingInfo.flight_number;

 Select plane_capacity into seats_total
 From seatingInfo, seatsReserved
 Where seatsReserved.flight_number = seatingInfo.flight_number;

 If seats_used < seats_total Then
 	Update Flight
 	Set plane_type = downsize_plane(seats_used);
 End If;
End;
/          

INSERT INTO Airline VALUES('001', 'Adlair Aviation', 'AA', 1978);
INSERT INTO Airline VALUES('002', 'Discovery Air Defence', 'DAD', 1973);
INSERT INTO Airline VALUES('003', 'Cougar Helicopters', 'CHC', 1982);
INSERT INTO Airline VALUES('004', 'Kootenay Direct Airlines', 'KDA', 1970);
INSERT INTO Airline VALUES('005', 'Orca Airways', 'OA', 1982);
INSERT INTO Airline VALUES('006', 'Porter Airlines', 'PA', 1991);
INSERT INTO Airline VALUES('007', 'Sky Regional Airlines', 'SRA', 1985);
INSERT INTO Airline VALUES('008', 'Superior Airways', 'SA', 1997);
INSERT INTO Airline VALUES('009', 'Tofino Air', 'TA', 1968);
INSERT INTO Airline VALUES('010', 'Transwest Air', 'TWA', 1980);
INSERT INTO Plane VALUES('A010', 'Airabon', 100, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '001');
INSERT INTO Plane VALUES('A020', 'Airaco', 110, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '001');
INSERT INTO Plane VALUES('A030', 'Airaco', 120, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '001');
INSERT INTO Plane VALUES('A040', 'Apache', 130, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '002');
INSERT INTO Plane VALUES('A050', 'Argus', 140, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '002');
INSERT INTO Plane VALUES('A060', 'Ascenr', 150, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '002');
INSERT INTO Plane VALUES('A070', 'Avenger', 160, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '003');
INSERT INTO Plane VALUES('A080', 'Aristoc', 170, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '003');
INSERT INTO Plane VALUES('A090', 'Aristo', 180, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '003');
INSERT INTO Plane VALUES('A100', 'Awesome', 190, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '004');
INSERT INTO Plane VALUES('B010', 'Bermuda', 200, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '004');
INSERT INTO Plane VALUES('B020', 'Black', 210, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '004');
INSERT INTO Plane VALUES('B030', 'Blackwe', 220, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '005');
INSERT INTO Plane VALUES('B040', 'Bobcat', 230, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '005');
INSERT INTO Plane VALUES('B050', 'Bolo', 240, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '005');
INSERT INTO Plane VALUES('B060', 'Boston', 250, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '006');
INSERT INTO Plane VALUES('B070', 'Buccane', 260, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '006');
INSERT INTO Plane VALUES('B080', 'Buffalo', 270, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '006');
INSERT INTO Plane VALUES('B090', 'Baltimo', 280, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '007');
INSERT INTO Plane VALUES('B100', 'Bat', 290, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '007');
INSERT INTO Plane VALUES('C010', 'Canso', 300, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '007');
INSERT INTO Plane VALUES('C020', 'Caravan', 310, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '008');
INSERT INTO Plane VALUES('C030', 'Catali', 320, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '008');
INSERT INTO Plane VALUES('C040', 'Chain Lig', 330, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '008');
INSERT INTO Plane VALUES('C050', 'Chesape', 340, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '009');
INSERT INTO Plane VALUES('C060', 'Clevel', 350, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '009');
INSERT INTO Plane VALUES('C070', 'Comma', 360, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '009');
INSERT INTO Plane VALUES('C080', 'Conest', 370, to_date('01-SEP-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '010');
INSERT INTO Plane VALUES('C090', 'Constella', 380, to_date('01-JAN-2016 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2016, '010');
INSERT INTO Plane VALUES('C100', 'Corne', 390, to_date('01-JAN-2015 10:00:00', 'DD-MON-YYYY HH24:MI:SS'), 2015, '010');
INSERT INTO Customer VALUES( '1', 'Mrs', 'Fletcher', 'Zahl', '0925960155412105', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '2', 'Mr', 'Lacresha', 'Stormer', '1928771949239723', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '3', 'Ms', 'Sonny', 'Mosley', '2740972684422356', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '4', 'Ms', 'Arla', 'Leffingwell', '1687753465790274', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '5', 'Mr', 'Aaron', 'Sievers', '9466795900245392', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '6', 'Ms', 'Retha', 'Piscopo', '5087889378041412', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '7', 'Mrs', 'Richard', 'Vero', '3306539430052511', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '8', 'Mr', 'Ghislaine', 'Socha', '4858880259571429', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '9', 'Mr', 'Jerry', 'Troyer', '4002750394454003', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '10', 'Ms', 'Annalee', 'Jeffries', '7903566145233481', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '11', 'Mrs', 'Anjanette', 'Arden', '4828637975618370', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '008' );
INSERT INTO Customer VALUES( '12', 'Mrs', 'Shakia', 'Aleman', '5450177331181679', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '13', 'Mr', 'Terra', 'Gillen', '2040897731588309', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '14', 'Ms', 'Tabitha', 'Bartz', '2977695633138067', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '15', 'Mr', 'Rhoda', 'Pam', '8081896060901242', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '16', 'Mr', 'Susana', 'Shupp', '4260293667491571', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '17', 'Ms', 'Angelika', 'Spillers', '9779035224613890', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '18', 'Ms', 'Kerry', 'Repka', '3285070853907952', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '19', 'Mrs', 'Terrance', 'Obrian', '6627965933077218', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '20', 'Mr', 'Elma', 'Rubino', '6739903265724270', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '008' );
INSERT INTO Customer VALUES( '21', 'Ms', 'Arletha', 'Stansfield', '6612694865279275', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '22', 'Ms', 'Michelina', 'Calnan', '1903702057489880', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '23', 'Ms', 'Georgene', 'Deutsch', '5472302036330156', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '24', 'Mr', 'Lucille', 'Gooch', '7465187637793432', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '25', 'Mr', 'Tyrone', 'Chinn', '4030438781467055', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '26', 'Mrs', 'Devora', 'Durazo', '4485766629361409', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '27', 'Mr', 'Barbie', 'Inoue', '8767031525488469', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '28', 'Mr', 'Marcelina', 'Marasco', '3436062410808102', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '29', 'Mrs', 'Alessandra', 'Klink', '9218063831672285', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '30', 'Mrs', 'Edwin', 'Larimore', '9398365084492982', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '31', 'Mr', 'Luise', 'Saladin', '8167709134111346', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '32', 'Ms', 'Ellen', 'Watters', '5722212280434629', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '33', 'Ms', 'Gita', 'Willie', '1479710886090589', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '34', 'Ms', 'Yuri', 'Landreneau', '8726260025513891', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '35', 'Mr', 'Kenny', 'Keogh', '1590840374379060', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '36', 'Mr', 'Magaly', 'Trainer', '9630684164485032', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '37', 'Mr', 'Elyse', 'Partington', '5403022837860112', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '006' );
INSERT INTO Customer VALUES( '38', 'Ms', 'Miquel', 'Seifert', '6738911843632040', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '39', 'Mr', 'Somer', 'Kulig', '6803794046748946', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '006' );
INSERT INTO Customer VALUES( '40', 'Mrs', 'Pilar', 'Hamby', '1857519204800094', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '006' );
INSERT INTO Customer VALUES( '41', 'Mr', 'Aubrey', 'Mccorvey', '0766113685312006', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '42', 'Mrs', 'Stephanie', 'Westmoreland', '6335990651583895', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '43', 'Mr', 'Hershel', 'Wrede', '6070002398885123', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '44', 'Ms', 'Brigid', 'Rocamora', '8103927397406382', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '45', 'Mr', 'Loraine', 'Plantz', '8253774871795186', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '46', 'Mrs', 'Tempie', 'Vancamp', '1155884795080422', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '47', 'Mrs', 'China', 'Yoshida', '8779895626927307', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '48', 'Mrs', 'Deeanna', 'Corrao', '5814014773856752', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '49', 'Mr', 'Mei', 'Capers', '3976685618977572', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '50', 'Mrs', 'Tarsha', 'Redwood', '9384769709555405', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '51', 'Mr', 'Celeste', 'Thome', '0916220567593315', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '52', 'Mr', 'Alonso', 'Leitz', '5004877173520340', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '53', 'Ms', 'Roseanna', 'Keenan', '4362693777046105', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '54', 'Mrs', 'Cierra', 'Debord', '4366394998690449', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '55', 'Mr', 'Clint', 'Jiggetts', '7297859802619057', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '56', 'Ms', 'Crystal', 'Almendarez', '7584596258850744', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '57', 'Ms', 'Marla', 'Auld', '1380038905693012', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '58', 'Ms', 'Janie', 'Kwiatkowski', '5231653236495000', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '59', 'Mrs', 'Adalberto', 'Stockbridge', '6671086375790837', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '60', 'Mrs', 'Stephanie', 'Shroyer', '3182730967992820', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '61', 'Mrs', 'Ed', 'Nagel', '7459928616091548', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '62', 'Mr', 'Janita', 'Mcfalls', '4359889201024886', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '63', 'Mrs', 'Vivien', 'Lovette', '9000673525900343', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '64', 'Mr', 'Ervin', 'Burdett', '1152408959839800', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '65', 'Mrs', 'Harmony', 'Burkett', '3348256121022713', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '66', 'Mr', 'Meggan', 'Mccarroll', '0789492115253690', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '67', 'Mr', 'Stacey', 'Burtt', '9030691894075211', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '008' );
INSERT INTO Customer VALUES( '68', 'Mrs', 'Hai', 'Barkett', '9956926050872882', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '69', 'Mr', 'Wendi', 'Marquis', '0284852366760470', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '70', 'Mr', 'Rocky', 'Bautista', '3448723877530947', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '71', 'Ms', 'Delbert', 'Aurand', '0822910303404887', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '72', 'Mrs', 'Darius', 'Stonerock', '2980600890866556', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '73', 'Mrs', 'Cheree', 'Hemsley', '0513570209779741', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '74', 'Ms', 'Landon', 'Purvines', '7639832656733124', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '75', 'Mrs', 'Adena', 'Tagg', '4606953450942911', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '76', 'Mrs', 'Heike', 'Rustad', '0377758810075886', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '77', 'Ms', 'Charlette', 'Collinson', '1679500686512538', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '78', 'Mr', 'Jannie', 'Carolina', '5313127596831769', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '79', 'Mr', 'Demetrius', 'Macmaster', '2490723662936561', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '80', 'Ms', 'Teisha', 'Banvelos', '6726715407584001', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '81', 'Mr', 'Crista', 'Bodner', '2845644645092239', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '82', 'Ms', 'Ron', 'Letchworth', '3578172468188930', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '83', 'Mrs', 'Ken', 'Earnshaw', '1374457312861148', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '84', 'Mr', 'Reena', 'Statton', '5994808175444707', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '85', 'Ms', 'Morton', 'Blackmore', '1467260458055537', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '006' );
INSERT INTO Customer VALUES( '86', 'Mr', 'Brigette', 'Facio', '0151573100567939', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '87', 'Ms', 'Ernie', 'Ostrem', '2787953291546492', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '88', 'Ms', 'Zachery', 'Evatt', '5912375826548609', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '89', 'Mr', 'Cindie', 'Silberman', '8158790726795354', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '90', 'Ms', 'Maryrose', 'Derrow', '4779543120255981', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '91', 'Ms', 'Kerry', 'Matsui', '6247325478936899', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '92', 'Ms', 'Joni', 'Bulfer', '6648089875664755', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '93', 'Mrs', 'Wanetta', 'Mckim', '6308145877869291', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '006' );
INSERT INTO Customer VALUES( '94', 'Mr', 'Akilah', 'Hammell', '6373890593425934', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '95', 'Ms', 'Fredrick', 'Maez', '9035258034737591', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '006' );
INSERT INTO Customer VALUES( '96', 'Mr', 'Mei', 'Atnip', '5340872549734698', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '97', 'Mr', 'Delmy', 'Rodrick', '2937722649454406', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '98', 'Mrs', 'Latina', 'Creviston', '5289438037852117', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '99', 'Mrs', 'Antone', 'Haag', '4962365684812724', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '100', 'Ms', 'Amber', 'Donalson', '8092117006284917', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '101', 'Mr', 'Tosha', 'Sibert', '1582336293938230', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '102', 'Mrs', 'Nathan', 'Delorey', '1798875046397636', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '103', 'Mr', 'Larry', 'Oyler', '8733829086039366', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '104', 'Ms', 'Dennise', 'Jelley', '4812546589943879', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '105', 'Mrs', 'Nam', 'Newbern', '4692757267094044', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '106', 'Mrs', 'Shonna', 'Mcevoy', '5247760210768454', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '107', 'Ms', 'Sixta', 'Kong', '4251592266134305', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '108', 'Mr', 'Kasie', 'Villeneuve', '7926648495482985', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '109', 'Mrs', 'Tomeka', 'Guillot', '9329924701550177', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '110', 'Mr', 'Barb', 'Mee', '9386883891084013', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '111', 'Mr', 'Doyle', 'Belgarde', '0353610168127638', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '112', 'Mrs', 'Precious', 'Marnell', '9342083512508207', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '113', 'Mrs', 'Mildred', 'Velasco', '3838906525631715', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '114', 'Mr', 'Jackqueline', 'Camburn', '6550218132084699', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '115', 'Ms', 'Nelly', 'Partin', '4751449548322276', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '116', 'Mrs', 'Darron', 'Coupe', '2432818775551611', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '117', 'Mrs', 'Marybeth', 'Esterline', '6184368929604450', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '118', 'Ms', 'Faustina', 'Nealon', '6719470914580324', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '119', 'Ms', 'Liana', 'Ocampo', '1906791924315700', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '120', 'Mrs', 'Tarra', 'Cassette', '8248838761364113', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '121', 'Mrs', 'Earlie', 'Kraemer', '0302195543036647', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '122', 'Mr', 'Asuncion', 'Stouffer', '2985672558828544', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '123', 'Ms', 'Marketta', 'Prenatt', '1783724136677709', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '124', 'Mr', 'Elsy', 'Lank', '9389315015776970', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '125', 'Ms', 'Marla', 'Cochran', '8822359325241334', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '126', 'Mr', 'Laci', 'Mentzer', '8056506173940219', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '127', 'Mrs', 'Rafael', 'Windham', '7728561027289376', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '128', 'Ms', 'Debbie', 'Benavente', '1309379811003143', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '129', 'Mr', 'Del', 'Brian', '1443737669772699', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '130', 'Mr', 'Starla', 'Kees', '3479708991029212', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '131', 'Ms', 'Coralee', 'Abbas', '4792658052564088', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '132', 'Ms', 'Valene', 'Hoffer', '7959058782356890', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '133', 'Mrs', 'Isaura', 'Depaolo', '5431172872813184', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '134', 'Mrs', 'Erna', 'Setton', '6643566800348011', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '135', 'Mrs', 'Charley', 'Correa', '8849240954424913', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '136', 'Mrs', 'Shelly', 'Ranieri', '7198032156230372', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '137', 'Mr', 'Linsey', 'Oles', '7158365727487974', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '138', 'Mr', 'Fatimah', 'Letson', '3774015913877580', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '139', 'Mrs', 'Deneen', 'Seawright', '8839413178281705', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '140', 'Ms', 'Sona', 'Mincey', '8708051633093964', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '141', 'Mrs', 'Jonathan', 'Peloquin', '5516099486593353', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '142', 'Mrs', 'Scotty', 'Medina', '2055884891875157', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '002' );
INSERT INTO Customer VALUES( '143', 'Ms', 'Enedina', 'Rosenau', '1286018976244890', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '144', 'Ms', 'Timothy', 'Boring', '8561923628296037', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '145', 'Mr', 'Kendra', 'Crigger', '8813476494259239', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '146', 'Mrs', 'Claudia', 'Cummins', '9874767178461448', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '147', 'Mr', 'Kelley', 'Blackwell', '5068450571196213', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '148', 'Mr', 'Felicitas', 'Obrien', '7045461402346632', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '149', 'Ms', 'Brendon', 'Hisey', '1985380667603407', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '150', 'Mr', 'Laraine', 'Cebula', '6758387316725343', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '151', 'Ms', 'Beverlee', 'Higuera', '5105941338078893', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '152', 'Mr', 'Saundra', 'Carner', '0603556364298715', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '153', 'Ms', 'Santiago', 'Rakes', '9177485357914311', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '154', 'Ms', 'Casandra', 'Contreras', '5755270867091203', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '155', 'Ms', 'Porter', 'Shum', '7307684542861768', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '156', 'Mr', 'Vernita', 'Kenner', '3540724780564472', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '157', 'Ms', 'Joetta', 'Castenada', '1991943409647160', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '158', 'Mrs', 'Milissa', 'Facer', '9022994311458114', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '159', 'Mr', 'Isis', 'Linsley', '4043885071505414', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '160', 'Mrs', 'Ilse', 'Brogden', '0386344899123240', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '161', 'Mrs', 'Elina', 'Praylow', '7548753078258917', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '162', 'Mrs', 'Krystyna', 'Feit', '5069897453109147', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '163', 'Mr', 'Elbert', 'Riess', '8325178728503031', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '164', 'Mrs', 'Devora', 'Arent', '7085577284607362', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '004' );
INSERT INTO Customer VALUES( '165', 'Mr', 'Danilo', 'Eury', '5110609792055480', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '166', 'Mrs', 'Leeanne', 'Hoefler', '6226323959689651', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '167', 'Mr', 'Marline', 'Hamlett', '5211836902367983', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '168', 'Mrs', 'Criselda', 'Kangas', '9423382222384883', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '169', 'Mr', 'Joette', 'Pages', '3118958492498616', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '170', 'Mr', 'Alison', 'Brewton', '7286147442841006', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '171', 'Mrs', 'Fidelia', 'Holsten', '2863696953479514', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '172', 'Mr', 'Rochelle', 'Culwell', '8641072927465910', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '173', 'Mr', 'Jolene', 'Brigman', '8920966686645729', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '174', 'Ms', 'Sharla', 'Sotomayor', '5210633070719559', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '175', 'Mrs', 'Luetta', 'Brault', '4950848721658899', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '176', 'Mr', 'Elaine', 'Didonato', '9919099442341743', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '177', 'Mrs', 'Nada', 'Fishburn', '7044150862763245', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '178', 'Mr', 'Christia', 'Gross', '9759187929021427', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '179', 'Mr', 'Douglas', 'Jessop', '5345247027473788', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '180', 'Mrs', 'Jae', 'Krebs', '4818542326918051', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '181', 'Ms', 'Shana', 'Dirksen', '3093180298552087', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '182', 'Mrs', 'Jacque', 'Kehr', '5208147981985118', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '183', 'Mrs', 'Annie', 'Eichenlaub', '9439375288972749', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '005' );
INSERT INTO Customer VALUES( '184', 'Ms', 'Dorthey', 'Hodgins', '4696943602778181', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '185', 'Mr', 'Velvet', 'Greenblatt', '4718982416785701', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '186', 'Mrs', 'Floy', 'Banner', '9869257720387362', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '003' );
INSERT INTO Customer VALUES( '187', 'Ms', 'Neil', 'Rothe', '6573614856419362', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '188', 'Ms', 'Carlene', 'Jessup', '6771335642196453', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '189', 'Ms', 'Ty', 'Hosking', '4600373635092450', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '007' );
INSERT INTO Customer VALUES( '190', 'Mrs', 'Tari', 'Conder', '7129212764264993', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '191', 'Mr', 'Sheba', 'Bartholomew', '6968671523051893', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '192', 'Ms', 'Robbie', 'Fitzwater', '7298767638804737', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '010' );
INSERT INTO Customer VALUES( '193', 'Ms', 'Debera', 'Jaggers', '3114044984373366', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '194', 'Mrs', 'Latrice', 'Sennett', '4171073684337873', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '195', 'Mr', 'Emeline', 'Ruggerio', '4918586100586097', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '196', 'Ms', 'Floyd', 'Krishnan', '8230451552920515', to_date('01/03/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '197', 'Mrs', 'Sammie', 'Luca', '0739853579327341', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '009' );
INSERT INTO Customer VALUES( '198', 'Mrs', 'Saturnina', 'Gardener', '0443330290385768', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', '001' );
INSERT INTO Customer VALUES( '199', 'Ms', 'Tod', 'Prather', '4518806813232501', to_date('01/01/2015', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Customer VALUES( '200', 'Ms', 'Norene', 'Henze', '2660962639565823', to_date('01/09/2016', 'dd/mm/yyyy'), 'Foo', 'Lititz', 'PA', '1234567890', 'foo@bar.null', NULL );
INSERT INTO Reservation VALUES( '1', '90', 258, '0221724026632400', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '2', '146', 258, '1387929325371722', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '3', '152', 258, '2116198902492780', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '4', '39', 258, '7151026475296732', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '5', '44', 258, '3882678930640084', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'DET' );
INSERT INTO Reservation VALUES( '6', '73', 258, '5710360390248563', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '7', '55', 258, '7551691882687350', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'MCH' );
INSERT INTO Reservation VALUES( '8', '166', 258, '6524756201799118', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'LTZ' );
INSERT INTO Reservation VALUES( '9', '71', 258, '4508190530414451', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'JFK' );
INSERT INTO Reservation VALUES( '10', '146', 258, '0096464532298328', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '11', '92', 258, '1180851086045317', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '12', '174', 258, '8082179904118303', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'CMP' );
INSERT INTO Reservation VALUES( '13', '156', 258, '0284577187114185', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'LTZ' );
INSERT INTO Reservation VALUES( '14', '9', 258, '3004757409902153', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'CMP' );
INSERT INTO Reservation VALUES( '15', '93', 258, '3404694690710672', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'MCH' );
INSERT INTO Reservation VALUES( '16', '114', 258, '6966041141018113', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'MCH' );
INSERT INTO Reservation VALUES( '17', '81', 258, '8441043384493249', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'JFK' );
INSERT INTO Reservation VALUES( '18', '199', 258, '4365348125439557', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '19', '161', 258, '3555048112799259', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'JFK', 'PHI' );
INSERT INTO Reservation VALUES( '20', '109', 258, '9455370502449182', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PHI', 'CMP' );
INSERT INTO Reservation VALUES( '21', '186', 258, '7758876052940257', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '22', '198', 258, '0150602393224075', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DCA', 'PHI' );
INSERT INTO Reservation VALUES( '23', '24', 258, '7261528033121825', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'JFK' );
INSERT INTO Reservation VALUES( '24', '80', 258, '8727284723868951', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '25', '54', 258, '9192917286517916', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'DCA' );
INSERT INTO Reservation VALUES( '26', '53', 258, '9502904124125840', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DET', 'PIT' );
INSERT INTO Reservation VALUES( '27', '183', 258, '1701503340210663', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '28', '60', 258, '5482500812740731', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DET', 'PIT' );
INSERT INTO Reservation VALUES( '29', '173', 258, '8201782273466156', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '30', '85', 258, '4870772728894585', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'LTZ' );
INSERT INTO Reservation VALUES( '31', '4', 258, '1545372435261888', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'PHI' );
INSERT INTO Reservation VALUES( '32', '26', 258, '2116834862299302', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'PHI' );
INSERT INTO Reservation VALUES( '33', '28', 258, '6095218376702578', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '34', '30', 258, '8152432033450873', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '35', '164', 258, '5750383653108868', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'PIT' );
INSERT INTO Reservation VALUES( '36', '153', 258, '3283832155136507', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '37', '94', 258, '7039937552011561', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '38', '139', 258, '1083314863588582', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'LTZ' );
INSERT INTO Reservation VALUES( '39', '118', 258, '2927435127287385', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'LTZ' );
INSERT INTO Reservation VALUES( '40', '82', 258, '6784105162294236', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '41', '96', 258, '6309526881760728', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'PHI' );
INSERT INTO Reservation VALUES( '42', '181', 258, '0242457598022412', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '43', '134', 258, '5629067150655403', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '44', '64', 258, '4753023490003222', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '45', '61', 258, '9820892002415380', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'CMP' );
INSERT INTO Reservation VALUES( '46', '175', 258, '1482189727152868', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'DET' );
INSERT INTO Reservation VALUES( '47', '123', 258, '1167080616495602', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '48', '163', 258, '7813791246516403', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '49', '113', 258, '5955372006552280', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'LTZ' );
INSERT INTO Reservation VALUES( '50', '33', 258, '9315002154227935', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '51', '109', 258, '1849120222730150', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '52', '22', 258, '1907385047861339', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'JFK' );
INSERT INTO Reservation VALUES( '53', '170', 258, '2343404465210603', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '54', '155', 258, '0900410845540770', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'CMP' );
INSERT INTO Reservation VALUES( '55', '4', 258, '5747401039873504', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'LTZ' );
INSERT INTO Reservation VALUES( '56', '27', 258, '5597179454551578', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '57', '151', 258, '5819046675879963', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'PIT' );
INSERT INTO Reservation VALUES( '58', '150', 258, '1140964271137123', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '59', '85', 258, '1822776595340319', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '60', '95', 258, '8455832189781927', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'CMP', 'JFK' );
INSERT INTO Reservation VALUES( '61', '176', 258, '2378761872012346', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'DCA' );
INSERT INTO Reservation VALUES( '62', '170', 258, '8949234596895459', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'JFK', 'MCH' );
INSERT INTO Reservation VALUES( '63', '21', 258, '0134266649526702', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'PIT' );
INSERT INTO Reservation VALUES( '64', '68', 258, '6202508971238079', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '65', '110', 258, '1566288531265683', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PHI' );
INSERT INTO Reservation VALUES( '66', '86', 258, '5413911612463347', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'CMP' );
INSERT INTO Reservation VALUES( '67', '184', 258, '6960424650017214', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '68', '139', 258, '1622826844611504', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'JFK', 'DCA' );
INSERT INTO Reservation VALUES( '69', '80', 258, '1351550656475852', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '70', '89', 258, '3616423011460680', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '71', '149', 258, '8142421208089885', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '72', '71', 258, '7515149776548748', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '73', '43', 258, '7439056650468111', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '74', '10', 258, '0321151903514663', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '75', '29', 258, '4320314959378760', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '76', '171', 258, '9079974478796918', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'MCH' );
INSERT INTO Reservation VALUES( '77', '107', 258, '6259065406789521', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '78', '108', 258, '1218665951081603', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'DET' );
INSERT INTO Reservation VALUES( '79', '33', 258, '3690032038211498', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '80', '2', 258, '9126528457174326', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'JFK', 'PHI' );
INSERT INTO Reservation VALUES( '81', '64', 258, '1383046036462468', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '82', '195', 258, '5317044297130119', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '83', '73', 258, '1275011586750420', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'CMP' );
INSERT INTO Reservation VALUES( '84', '135', 258, '5409003902994644', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '85', '101', 258, '8214733746684583', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'CMP' );
INSERT INTO Reservation VALUES( '86', '177', 258, '6090575807683205', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'CMP', 'MCH' );
INSERT INTO Reservation VALUES( '87', '44', 258, '2193913457401326', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '88', '31', 258, '5925847337717640', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'CMP' );
INSERT INTO Reservation VALUES( '89', '27', 258, '6979070743483314', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'CMP' );
INSERT INTO Reservation VALUES( '90', '187', 258, '7747258975279820', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'CMP' );
INSERT INTO Reservation VALUES( '91', '130', 258, '1558205467817707', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '92', '61', 258, '3350963729198060', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '93', '8', 258, '6502548021977311', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'DCA' );
INSERT INTO Reservation VALUES( '94', '37', 258, '5468838323799229', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'MCH' );
INSERT INTO Reservation VALUES( '95', '33', 258, '9664977211654030', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '96', '29', 258, '5853034275968031', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '97', '157', 258, '7700932833085045', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'PIT' );
INSERT INTO Reservation VALUES( '98', '196', 258, '1263866907350563', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'LTZ' );
INSERT INTO Reservation VALUES( '99', '68', 258, '3785160199797085', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '100', '36', 258, '0494651337090997', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'MCH' );
INSERT INTO Reservation VALUES( '101', '31', 258, '0604536918839896', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '102', '181', 258, '5171438752056983', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '103', '124', 258, '1033065092457329', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '104', '120', 258, '4167703750948743', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'DCA' );
INSERT INTO Reservation VALUES( '105', '110', 258, '1357211715834165', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'JFK', 'DET' );
INSERT INTO Reservation VALUES( '106', '10', 258, '9427795520203061', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '107', '36', 258, '4919282268578839', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'DCA' );
INSERT INTO Reservation VALUES( '108', '158', 258, '8945326024290377', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'LTZ' );
INSERT INTO Reservation VALUES( '109', '12', 258, '0603391897835045', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '110', '7', 258, '7271610916449476', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '111', '193', 258, '9778023026793622', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DCA' );
INSERT INTO Reservation VALUES( '112', '75', 258, '8253902319489051', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '113', '50', 258, '5886075010813239', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '114', '15', 258, '6174927703836450', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'DCA' );
INSERT INTO Reservation VALUES( '115', '125', 258, '4260247982864218', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '116', '1', 258, '9979594677139258', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '117', '11', 258, '0657409007514737', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '118', '45', 258, '6383354944298018', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '119', '71', 258, '5150001985424175', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'LTZ' );
INSERT INTO Reservation VALUES( '120', '7', 258, '5117503142255010', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '121', '181', 258, '6267345245785908', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '122', '177', 258, '5641026212410413', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '123', '173', 258, '8640943122798658', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '124', '40', 258, '7898581209253320', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '125', '133', 258, '6619565199076072', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '126', '84', 258, '7865154783497039', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'LTZ' );
INSERT INTO Reservation VALUES( '127', '80', 258, '3825249852755428', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'DCA' );
INSERT INTO Reservation VALUES( '128', '92', 258, '9992953427110479', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'JFK', 'DCA' );
INSERT INTO Reservation VALUES( '129', '30', 258, '5610561644898851', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '130', '6', 258, '3067901040550637', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '131', '120', 258, '5742859809257924', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PHI', 'CMP' );
INSERT INTO Reservation VALUES( '132', '183', 258, '1659284020416770', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'DET' );
INSERT INTO Reservation VALUES( '133', '60', 258, '4703348435838965', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '134', '81', 258, '9493126963174045', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'MCH' );
INSERT INTO Reservation VALUES( '135', '146', 258, '3084366028507933', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'CMP' );
INSERT INTO Reservation VALUES( '136', '134', 258, '6704219360303452', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'PIT' );
INSERT INTO Reservation VALUES( '137', '102', 258, '2761639422038535', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '138', '149', 258, '6660742818440972', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '139', '54', 258, '4197553531741486', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '140', '145', 258, '5562934288354341', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'CMP' );
INSERT INTO Reservation VALUES( '141', '98', 258, '7825433476842676', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'LTZ' );
INSERT INTO Reservation VALUES( '142', '182', 258, '7278514208863407', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '143', '124', 258, '3726468875010390', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '144', '123', 258, '1055103007977254', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DET', 'PHI' );
INSERT INTO Reservation VALUES( '145', '170', 258, '1878673722713961', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '146', '17', 258, '5654662574538055', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'CMP' );
INSERT INTO Reservation VALUES( '147', '155', 258, '7511242397446240', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'LTZ' );
INSERT INTO Reservation VALUES( '148', '120', 258, '1810784958011338', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'MCH' );
INSERT INTO Reservation VALUES( '149', '28', 258, '5131039253948741', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '150', '180', 258, '8164644516840882', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'JFK' );
INSERT INTO Reservation VALUES( '151', '25', 258, '8301941213201036', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '152', '181', 258, '4021325671603173', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '153', '85', 258, '6755332691793149', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'LTZ' );
INSERT INTO Reservation VALUES( '154', '75', 258, '4025835028062524', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '155', '87', 258, '5971340589448487', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '156', '155', 258, '3167442935265723', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '157', '189', 258, '8173486385032204', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '158', '101', 258, '6187254767678517', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PHI' );
INSERT INTO Reservation VALUES( '159', '5', 258, '7456214625279776', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '160', '189', 258, '0906368820835897', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '161', '122', 258, '8605351979214157', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'CMP' );
INSERT INTO Reservation VALUES( '162', '19', 258, '9236789516847269', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'JFK' );
INSERT INTO Reservation VALUES( '163', '80', 258, '1455622415625033', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'PHI' );
INSERT INTO Reservation VALUES( '164', '37', 258, '6270340277736431', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '165', '33', 258, '8055821220798957', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '166', '99', 258, '9860844408559755', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '167', '54', 258, '3161609156233294', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'PIT' );
INSERT INTO Reservation VALUES( '168', '42', 258, '3239328460357972', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '169', '154', 258, '5523193928329672', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '170', '185', 258, '2483112850895063', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'JFK', 'PIT' );
INSERT INTO Reservation VALUES( '171', '3', 258, '6647241702404091', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '172', '124', 258, '4613259484314282', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PHI' );
INSERT INTO Reservation VALUES( '173', '14', 258, '5783123207953606', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'PHI' );
INSERT INTO Reservation VALUES( '174', '185', 258, '8698839260230395', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'LTZ' );
INSERT INTO Reservation VALUES( '175', '175', 258, '4587673761093644', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'JFK', 'DCA' );
INSERT INTO Reservation VALUES( '176', '193', 258, '0544574228011055', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'DET' );
INSERT INTO Reservation VALUES( '177', '72', 258, '4273102512625616', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'MCH' );
INSERT INTO Reservation VALUES( '178', '196', 258, '2019635991323505', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '179', '141', 258, '1780715995293671', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'PHI' );
INSERT INTO Reservation VALUES( '180', '133', 258, '4274825059508443', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'CMP' );
INSERT INTO Reservation VALUES( '181', '49', 258, '6142620797155410', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '182', '159', 258, '1681570760324843', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '183', '82', 258, '0185805401629694', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'JFK' );
INSERT INTO Reservation VALUES( '184', '176', 258, '3896901337973530', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DCA', 'JFK' );
INSERT INTO Reservation VALUES( '185', '126', 258, '5423943011774235', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'PHI' );
INSERT INTO Reservation VALUES( '186', '195', 258, '4117293745485261', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '187', '46', 258, '1169006377608568', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '188', '151', 258, '1110981869880729', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '189', '26', 258, '6303416581479802', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DET', 'DCA' );
INSERT INTO Reservation VALUES( '190', '84', 258, '1787044412003981', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DET', 'LTZ' );
INSERT INTO Reservation VALUES( '191', '56', 258, '2605999738893152', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '192', '107', 258, '1703537824301275', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '193', '91', 258, '4005650188592156', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '194', '7', 258, '9224598922249460', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '195', '30', 258, '1204188535886887', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '196', '172', 258, '9106258745707335', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '197', '148', 258, '5316526413014439', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'JFK', 'MCH' );
INSERT INTO Reservation VALUES( '198', '11', 258, '7392232532550946', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'MCH' );
INSERT INTO Reservation VALUES( '199', '109', 258, '6240410167647009', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '200', '175', 258, '6731017096316770', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '201', '151', 258, '5561618565301405', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '202', '151', 258, '0577252520146675', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'CMP', 'LTZ' );
INSERT INTO Reservation VALUES( '203', '114', 258, '5821995639440951', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '204', '135', 258, '9274083494435283', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '205', '96', 258, '5627809111201432', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '206', '165', 258, '5332462744351446', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '207', '192', 258, '5685800523065229', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'PHI' );
INSERT INTO Reservation VALUES( '208', '144', 258, '5738607510261351', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'PIT' );
INSERT INTO Reservation VALUES( '209', '186', 258, '8757364548466703', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '210', '199', 258, '7056469686790143', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '211', '45', 258, '8008849093590783', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '212', '111', 258, '0188574114626841', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'LTZ', 'PHI' );
INSERT INTO Reservation VALUES( '213', '16', 258, '3422421332506969', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'JFK' );
INSERT INTO Reservation VALUES( '214', '21', 258, '3945341240885526', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'DET' );
INSERT INTO Reservation VALUES( '215', '39', 258, '6527922336025544', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'DCA' );
INSERT INTO Reservation VALUES( '216', '126', 258, '1923494827753893', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'PIT' );
INSERT INTO Reservation VALUES( '217', '171', 258, '5145226225060658', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'DET' );
INSERT INTO Reservation VALUES( '218', '72', 258, '6453255379800047', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '219', '36', 258, '7115660913960758', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'JFK', 'DCA' );
INSERT INTO Reservation VALUES( '220', '117', 258, '1817314871360832', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DCA', 'PIT' );
INSERT INTO Reservation VALUES( '221', '189', 258, '9553798609085142', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'CMP' );
INSERT INTO Reservation VALUES( '222', '26', 258, '0321944929602075', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '223', '75', 258, '7033218689679716', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'DCA' );
INSERT INTO Reservation VALUES( '224', '93', 258, '6479868630377346', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '225', '144', 258, '8492051160048348', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '226', '125', 258, '0915527202542899', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'JFK', 'PIT' );
INSERT INTO Reservation VALUES( '227', '155', 258, '3930969675514969', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'JFK' );
INSERT INTO Reservation VALUES( '228', '117', 258, '6056429674334741', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'MCH' );
INSERT INTO Reservation VALUES( '229', '52', 258, '2460595170164769', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'LTZ' );
INSERT INTO Reservation VALUES( '230', '167', 258, '9703681601324113', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'JFK' );
INSERT INTO Reservation VALUES( '231', '14', 258, '9295730430742088', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'CMP' );
INSERT INTO Reservation VALUES( '232', '30', 258, '5811758705558403', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '233', '114', 258, '9275206563160586', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '234', '126', 258, '2527516410585314', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '235', '180', 258, '6979073218353469', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'PIT' );
INSERT INTO Reservation VALUES( '236', '94', 258, '0079487064720005', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '237', '118', 258, '7095058336971294', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'DCA' );
INSERT INTO Reservation VALUES( '238', '34', 258, '4678888208861485', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'PIT' );
INSERT INTO Reservation VALUES( '239', '47', 258, '6747308716227275', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '240', '149', 258, '4525407555284541', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'CMP', 'MCH' );
INSERT INTO Reservation VALUES( '241', '190', 258, '2119422789279762', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PHI', 'MCH' );
INSERT INTO Reservation VALUES( '242', '196', 258, '6931308808272763', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'DCA' );
INSERT INTO Reservation VALUES( '243', '178', 258, '0337633231822395', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'CMP', 'DCA' );
INSERT INTO Reservation VALUES( '244', '200', 258, '9591336214775635', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DCA' );
INSERT INTO Reservation VALUES( '245', '89', 258, '6548766062570085', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '246', '172', 258, '0090116655630741', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'LTZ' );
INSERT INTO Reservation VALUES( '247', '81', 258, '2349793739159618', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '248', '143', 258, '7547926880029686', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'JFK' );
INSERT INTO Reservation VALUES( '249', '35', 258, '5462619621140911', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'DET' );
INSERT INTO Reservation VALUES( '250', '47', 258, '0379042868395037', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '251', '170', 258, '7140772584927753', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '252', '150', 258, '4542971779178539', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'DCA' );
INSERT INTO Reservation VALUES( '253', '16', 258, '3959973677205024', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '254', '140', 258, '9519844248308206', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DCA' );
INSERT INTO Reservation VALUES( '255', '78', 258, '4788287353648646', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '256', '108', 258, '1814337177509367', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'LTZ' );
INSERT INTO Reservation VALUES( '257', '194', 258, '7393205866828564', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'PHI' );
INSERT INTO Reservation VALUES( '258', '136', 258, '1252249721866958', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'MCH' );
INSERT INTO Reservation VALUES( '259', '41', 258, '7749002125158180', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'MCH', 'DET' );
INSERT INTO Reservation VALUES( '260', '189', 258, '7200326691066830', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '261', '32', 258, '7501170795728252', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'PHI' );
INSERT INTO Reservation VALUES( '262', '200', 258, '6542590820300024', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '263', '119', 258, '7652752707210193', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'CMP', 'PHI' );
INSERT INTO Reservation VALUES( '264', '7', 258, '9263923003622660', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'PIT' );
INSERT INTO Reservation VALUES( '265', '44', 258, '2262858202440470', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '266', '18', 258, '8902106435726508', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'DCA' );
INSERT INTO Reservation VALUES( '267', '31', 258, '0824446268835189', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '268', '112', 258, '0687100958582172', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'DET' );
INSERT INTO Reservation VALUES( '269', '190', 258, '9722714773882696', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'PHI', 'DET' );
INSERT INTO Reservation VALUES( '270', '145', 258, '3027569981311186', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'LTZ', 'DET' );
INSERT INTO Reservation VALUES( '271', '192', 258, '0387439287331421', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'PHI' );
INSERT INTO Reservation VALUES( '272', '122', 258, '2683847674072472', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'MCH', 'JFK' );
INSERT INTO Reservation VALUES( '273', '54', 258, '2706822918712519', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'CMP', 'DET' );
INSERT INTO Reservation VALUES( '274', '80', 258, '0262233754462878', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '275', '133', 258, '6070155667601803', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'PHI' );
INSERT INTO Reservation VALUES( '276', '13', 258, '5608590072973824', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'DCA' );
INSERT INTO Reservation VALUES( '277', '136', 258, '7484007948652936', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'PIT', 'CMP' );
INSERT INTO Reservation VALUES( '278', '20', 258, '7805298481805819', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'PIT', 'JFK' );
INSERT INTO Reservation VALUES( '279', '131', 258, '1825040837885407', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '280', '37', 258, '4606316714102371', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'DCA' );
INSERT INTO Reservation VALUES( '281', '58', 258, '3847048669259961', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'LTZ' );
INSERT INTO Reservation VALUES( '282', '114', 258, '4837565472413051', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DCA', 'JFK' );
INSERT INTO Reservation VALUES( '283', '172', 258, '3103064260603413', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'DET', 'LTZ' );
INSERT INTO Reservation VALUES( '284', '154', 258, '0879347380748263', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'JFK' );
INSERT INTO Reservation VALUES( '285', '146', 258, '0477483492268344', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'DET' );
INSERT INTO Reservation VALUES( '286', '122', 258, '4379487660987411', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'LTZ' );
INSERT INTO Reservation VALUES( '287', '199', 258, '8017768597976198', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'MCH' );
INSERT INTO Reservation VALUES( '288', '195', 258, '1032411142429899', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'CMP' );
INSERT INTO Reservation VALUES( '289', '106', 258, '6263431064255793', to_date('01/01/2015', 'dd/mm/yyyy'), 'N', 'JFK', 'PIT' );
INSERT INTO Reservation VALUES( '290', '196', 258, '7269230136149977', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'MCH' );
INSERT INTO Reservation VALUES( '291', '125', 258, '1332252897384173', to_date('01/03/2015', 'dd/mm/yyyy'), 'N', 'DCA', 'MCH' );
INSERT INTO Reservation VALUES( '292', '196', 258, '5281330111106401', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DET', 'MCH' );
INSERT INTO Reservation VALUES( '293', '51', 258, '3835581715617329', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'MCH', 'PIT' );
INSERT INTO Reservation VALUES( '294', '66', 258, '0306600926812539', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'LTZ', 'JFK' );
INSERT INTO Reservation VALUES( '295', '74', 258, '5798596953557441', to_date('01/09/2016', 'dd/mm/yyyy'), 'N', 'DCA', 'DET' );
INSERT INTO Reservation VALUES( '296', '15', 258, '7445532782702962', to_date('01/01/2015', 'dd/mm/yyyy'), 'Y', 'JFK', 'MCH' );
INSERT INTO Reservation VALUES( '297', '102', 258, '0730227611957811', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'DET', 'MCH' );
INSERT INTO Reservation VALUES( '298', '51', 258, '2846774153578506', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'LTZ', 'PIT' );
INSERT INTO Reservation VALUES( '299', '200', 258, '3852388752797099', to_date('01/09/2016', 'dd/mm/yyyy'), 'Y', 'CMP', 'MCH' );
INSERT INTO Reservation VALUES( '300', '151', 258, '3802251428886660', to_date('01/03/2015', 'dd/mm/yyyy'), 'Y', 'PIT', 'PHI' );
INSERT INTO Flight VALUES( '1', '001', 'A020', 'PHI', 'LTZ', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '2', '005', 'B030', 'CMP', 'DET', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '3', '005', 'B030', 'CMP', 'PIT', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '4', '010', 'C100', 'PIT', 'MCH', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '5', '001', 'A010', 'DCA', 'PHI', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '6', '009', 'C070', 'DET', 'CMP', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '7', '010', 'C100', 'CMP', 'MCH', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '8', '005', 'B030', 'DCA', 'PIT', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '9', '009', 'C070', 'PIT', 'PHI', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '10', '006', 'B070', 'LTZ', 'PHI', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '11', '001', 'A010', 'PHI', 'DCA', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '12', '001', 'A010', 'DET', 'CMP', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '13', '006', 'B070', 'DET', 'DCA', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '14', '010', 'C100', 'LTZ', 'PIT', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '15', '009', 'C070', 'DET', 'LTZ', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '16', '009', 'C070', 'DET', 'MCH', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '17', '001', 'A020', 'LTZ', 'PIT', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '18', '006', 'B070', 'CMP', 'PIT', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '19', '010', 'C100', 'LTZ', 'PIT', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '20', '001', 'A010', 'DCA', 'DET', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '21', '001', 'A010', 'MCH', 'LTZ', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '22', '001', 'A020', 'LTZ', 'DCA', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '23', '009', 'C070', 'CMP', 'PHI', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '24', '010', 'C100', 'CMP', 'MCH', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '25', '002', 'A060', 'DCA', 'DET', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '26', '010', 'C100', 'JFK', 'CMP', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '27', '001', 'A020', 'DCA', 'JFK', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '28', '002', 'A060', 'PIT', 'LTZ', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '29', '010', 'C100', 'PHI', 'LTZ', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '30', '005', 'B030', 'DET', 'CMP', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '31', '002', 'A060', 'CMP', 'PHI', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '32', '001', 'A020', 'PIT', 'DET', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '33', '009', 'C070', 'PIT', 'JFK', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '34', '002', 'A060', 'DET', 'PIT', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '35', '010', 'C100', 'LTZ', 'CMP', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '36', '002', 'A060', 'LTZ', 'JFK', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '37', '010', 'C100', 'JFK', 'PHI', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '38', '005', 'B030', 'DET', 'DCA', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '39', '002', 'A060', 'PHI', 'PIT', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '40', '001', 'A020', 'DET', 'DCA', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '41', '010', 'C100', 'PIT', 'DCA', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '42', '010', 'C100', 'DET', 'PHI', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '43', '009', 'C070', 'PIT', 'JFK', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '44', '010', 'C100', 'PIT', 'JFK', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '45', '006', 'B070', 'PHI', 'PIT', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '46', '001', 'A020', 'DET', 'LTZ', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '47', '009', 'C070', 'PIT', 'LTZ', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '48', '009', 'C070', 'DET', 'PHI', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '49', '006', 'B070', 'LTZ', 'CMP', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '50', '006', 'B070', 'PIT', 'JFK', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '51', '009', 'C070', 'LTZ', 'CMP', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '52', '005', 'B030', 'DET', 'LTZ', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '53', '006', 'B070', 'DET', 'PHI', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '54', '010', 'C100', 'CMP', 'DET', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '55', '001', 'A020', 'PHI', 'JFK', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '56', '005', 'B030', 'MCH', 'PHI', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '57', '009', 'C070', 'PHI', 'CMP', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '58', '009', 'C070', 'PIT', 'PHI', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '59', '009', 'C070', 'DCA', 'LTZ', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '60', '001', 'A010', 'DET', 'LTZ', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '61', '002', 'A060', 'DET', 'DCA', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '62', '001', 'A020', 'MCH', 'JFK', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '63', '001', 'A010', 'JFK', 'MCH', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '64', '005', 'B030', 'DET', 'PHI', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '65', '001', 'A020', 'DET', 'JFK', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '66', '005', 'B030', 'MCH', 'PHI', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '67', '002', 'A060', 'DCA', 'LTZ', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '68', '005', 'B030', 'MCH', 'LTZ', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '69', '001', 'A010', 'PIT', 'JFK', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '70', '010', 'C100', 'JFK', 'DCA', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '71', '006', 'B070', 'DCA', 'PIT', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '72', '010', 'C100', 'DET', 'DCA', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '73', '010', 'C100', 'DET', 'PHI', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '74', '010', 'C100', 'DET', 'PIT', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '75', '005', 'B030', 'DCA', 'CMP', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '76', '009', 'C070', 'DCA', 'LTZ', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '77', '001', 'A020', 'PIT', 'JFK', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '78', '009', 'C070', 'JFK', 'LTZ', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '79', '009', 'C070', 'DCA', 'CMP', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '80', '009', 'C070', 'LTZ', 'MCH', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '81', '001', 'A010', 'DCA', 'PHI', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '82', '005', 'B030', 'JFK', 'PIT', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '83', '006', 'B070', 'PHI', 'DCA', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '84', '005', 'B030', 'MCH', 'DET', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '85', '009', 'C070', 'DET', 'LTZ', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '86', '002', 'A060', 'MCH', 'LTZ', '1200', '2200', '--TWTFS' );
INSERT INTO Flight VALUES( '87', '001', 'A020', 'PIT', 'JFK', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '88', '009', 'C070', 'DET', 'PHI', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '89', '005', 'B030', 'DET', 'MCH', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '90', '001', 'A010', 'LTZ', 'CMP', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '91', '010', 'C100', 'DET', 'PIT', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '92', '001', 'A020', 'LTZ', 'PHI', '1200', '2200', 'SMTWT--' );
INSERT INTO Flight VALUES( '93', '009', 'C070', 'DCA', 'MCH', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '94', '002', 'A060', 'DCA', 'JFK', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '95', '005', 'B030', 'PHI', 'DET', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '96', '010', 'C100', 'MCH', 'PIT', '1200', '2200', '-M-WT--' );
INSERT INTO Flight VALUES( '97', '010', 'C100', 'CMP', 'PIT', '1200', '2200', 'S--WTF-' );
INSERT INTO Flight VALUES( '98', '010', 'C100', 'DCA', 'PHI', '1200', '2200', 'SMTW-F-' );
INSERT INTO Flight VALUES( '99', '009', 'C070', 'LTZ', 'DCA', '1200', '2200', '-MTWTF-' );
INSERT INTO Flight VALUES( '100', '005', 'B030', 'CMP', 'PHI', '1200', '2200', 'S--WTF-' );
INSERT INTO Price VALUES( 'PHI', 'LTZ', '007', 240, 118 );
INSERT INTO Price VALUES( 'CMP', 'DET', '002', 219, 151 );
INSERT INTO Price VALUES( 'CMP', 'PIT', '005', 294, 126 );
INSERT INTO Price VALUES( 'PIT', 'MCH', '010', 271, 184 );
INSERT INTO Price VALUES( 'DCA', 'PHI', '009', 241, 187 );
INSERT INTO Price VALUES( 'DET', 'CMP', '007', 207, 148 );
INSERT INTO Price VALUES( 'CMP', 'MCH', '009', 234, 148 );
INSERT INTO Price VALUES( 'DCA', 'PIT', '003', 278, 152 );
INSERT INTO Price VALUES( 'PIT', 'PHI', '005', 271, 132 );
INSERT INTO Price VALUES( 'LTZ', 'PHI', '004', 230, 190 );
INSERT INTO Price VALUES( 'PHI', 'DCA', '002', 236, 188 );
INSERT INTO Price VALUES( 'DET', 'DCA', '009', 232, 166 );
INSERT INTO Price VALUES( 'LTZ', 'PIT', '007', 285, 136 );
INSERT INTO Price VALUES( 'DET', 'LTZ', '005', 284, 122 );
INSERT INTO Price VALUES( 'DET', 'MCH', '007', 227, 140 );
INSERT INTO Price VALUES( 'DCA', 'DET', '004', 267, 174 );
INSERT INTO Price VALUES( 'MCH', 'LTZ', '006', 220, 128 );
INSERT INTO Price VALUES( 'LTZ', 'DCA', '008', 274, 157 );
INSERT INTO Price VALUES( 'CMP', 'PHI', '001', 258, 177 );
INSERT INTO Price VALUES( 'JFK', 'CMP', '002', 227, 108 );
INSERT INTO Price VALUES( 'DCA', 'JFK', '009', 270, 123 );
INSERT INTO Price VALUES( 'PIT', 'LTZ', '001', 252, 168 );
INSERT INTO Price VALUES( 'PIT', 'DET', '008', 227, 148 );
INSERT INTO Price VALUES( 'PIT', 'JFK', '006', 277, 156 );
INSERT INTO Price VALUES( 'DET', 'PIT', '007', 286, 138 );
INSERT INTO Price VALUES( 'LTZ', 'CMP', '007', 266, 180 );
INSERT INTO Price VALUES( 'LTZ', 'JFK', '008', 255, 124 );
INSERT INTO Price VALUES( 'JFK', 'PHI', '005', 223, 101 );
INSERT INTO Price VALUES( 'PHI', 'PIT', '009', 219, 131 );
INSERT INTO Price VALUES( 'PIT', 'DCA', '003', 260, 184 );
INSERT INTO Price VALUES( 'DET', 'PHI', '001', 240, 102 );
INSERT INTO Price VALUES( 'PHI', 'JFK', '006', 227, 195 );
INSERT INTO Price VALUES( 'MCH', 'PHI', '004', 249, 115 );
INSERT INTO Price VALUES( 'PHI', 'CMP', '005', 225, 181 );
INSERT INTO Price VALUES( 'DCA', 'LTZ', '010', 272, 158 );
INSERT INTO Price VALUES( 'MCH', 'JFK', '006', 283, 174 );
INSERT INTO Price VALUES( 'JFK', 'MCH', '010', 249, 164 );
INSERT INTO Price VALUES( 'DET', 'JFK', '003', 229, 145 );
INSERT INTO Price VALUES( 'JFK', 'DCA', '003', 274, 116 );
INSERT INTO Price VALUES( 'DCA', 'CMP', '007', 269, 148 );
INSERT INTO Price VALUES( 'JFK', 'LTZ', '007', 288, 138 );
INSERT INTO Price VALUES( 'LTZ', 'MCH', '006', 206, 125 );
INSERT INTO Price VALUES( 'JFK', 'PIT', '010', 247, 182 );
INSERT INTO Price VALUES( 'MCH', 'DET', '009', 241, 154 );
INSERT INTO Price VALUES( 'DCA', 'MCH', '003', 279, 160 );
INSERT INTO Price VALUES( 'PHI', 'DET', '009', 287, 151 );
INSERT INTO Price VALUES( 'MCH', 'PIT', '003', 250, 131 );
INSERT INTO Reservation_detail VALUES( '1', '91', to_date('03/09/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '1', '1', to_date('03/09/2016', 'mm/dd/yyyy'), 2);
INSERT INTO Reservation_detail VALUES( '1', '53', to_date('03/09/2016', 'mm/dd/yyyy'), 3);
INSERT INTO Reservation_detail VALUES( '2', '92', to_date('04/10/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '2', '93', to_date('04/10/2016', 'mm/dd/yyyy'), 2);
INSERT INTO Reservation_detail VALUES( '3', '94', to_date('02/07/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '3', '95', to_date('02/07/2016', 'mm/dd/yyyy'), 2);
INSERT INTO Reservation_detail VALUES( '3', '96', to_date('02/07/2016', 'mm/dd/yyyy'), 3);
INSERT INTO Reservation_detail VALUES( '7', '97', to_date('08/19/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '8', '98', to_date('12/16/2015', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '9', '92', to_date('04/10/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '10', '93', to_date('05/08/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '11', '94', to_date('02/07/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '12', '95', to_date('06/06/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '13', '96', to_date('07/11/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '14', '97', to_date('08/19/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '15', '98', to_date('12/16/2015', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '16', '92', to_date('04/10/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '17', '93', to_date('05/08/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '18', '94', to_date('02/07/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '19', '95', to_date('06/06/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '20', '96', to_date('07/11/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '21', '97', to_date('08/19/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '22', '98', to_date('12/16/2015', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '23', '92', to_date('04/10/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '24', '93', to_date('05/08/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '25', '94', to_date('02/07/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '26', '95', to_date('06/06/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '27', '96', to_date('07/11/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '28', '97', to_date('08/19/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '29', '98', to_date('12/16/2015', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '30', '92', to_date('04/10/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '31', '93', to_date('05/08/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '32', '94', to_date('02/07/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '33', '95', to_date('06/06/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '34', '96', to_date('07/11/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '35', '97', to_date('08/19/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '36', '98', to_date('12/16/2015', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '37', '92', to_date('04/10/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '39', '93', to_date('05/08/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '40', '94', to_date('02/07/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '45', '95', to_date('06/06/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '46', '96', to_date('07/11/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '47', '97', to_date('08/19/2016', 'mm/dd/yyyy'), 1);
INSERT INTO Reservation_detail VALUES( '48', '98', to_date('12/16/2015', 'mm/dd/yyyy'), 1);               