------------- Création de base relationnelle a partir des données HNSC --------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------

-- Création base HNSC -- 
CREATE DATABASE hnsc;
USE hnsc;
describe clinical_HNSC;

-- Verification de la clé patient --
SELECT
    COUNT(*) AS nb_lignes,
    COUNT(DISTINCT bcr_patient_barcode) AS nb_patients
FROM clinical_HNSC;

SELECT *
FROM clinical_HNSC
WHERE bcr_patient_barcode IS NULL;

-- Déduplication des patients : création d'une base sans doublons --

CREATE TABLE clinical_HNSC_cl AS
SELECT *
FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY bcr_patient_barcode
              ORDER BY (CASE WHEN overall_survival IS NOT NULL THEN 0 ELSE 1 END), days_to_last_followup DESC
           ) AS rn
    FROM clinical_HNSC
) t
WHERE rn = 1;

SELECT count(*) as nb_ligne,
		count(distinct bcr_patient_barcode) as nb_patients
FROM clinical_HNSC_cl;


-- Création table patients--
create table patients (
patient_id varchar(20) PRIMARY KEY,
age_at_diagnosis int,
gender varchar (10),
hpv_status varchar (20),
alcohol_use varchar (20),
smoking_history int);

INSERT INTO patients (patient_id,
    age_at_diagnosis,
    gender,
    hpv_status,
    alcohol_use,
    smoking_history)

SELECT
    bcr_patient_barcode,
    age_at_diagnosis,
    gender,
    hpv_status_by_p16,
    known_history_of_alcohol_use,
    NULLIF(tobacco_smoking_history, '')
FROM clinical_HNSC_cl;

-- Création table tumor --

create table tumor (
	patient_id varchar (20),
	pathologic_stage varchar (10),
	clinical_stage varchar (10),
	perineural_invasion  varchar (10), 
	foreign key (patient_id) references patients (patient_id)
		ON DELETE CASCADE
		ON UPDATE CASCADE);

select  max(length(pathologic_stage) )
from clinical_HNSC_cl;

ALTER TABLE tumor 
Modify pathologic_stage varchar (20);


INSERT INTO tumor( 
	patient_id,
	pathologic_stage,
	clinical_stage,
	perineural_invasion)

SELECT 
	bcr_patient_barcode,
	pathologic_stage,
	clinical_stage,
	perineural_invasion
from clinical_HNSC_cl;

select * 
from clinical_HNSC;

alter table tumor 
add column lymphvascular_invasion varchar (10) ;

update tumor t
join clinical_HNSC_cl cl
on t.patient_id=cl.bcr_patient_barcode
set lymphvascular_invasion=`lymphvascular invasion`; 

-- Table survie --
create table survival (
	patient_id varchar (20),
	time int,
	event tinyint,
	FOREIGN KEY (patient_id) references patients (patient_id)
    );

-- CREATION DES OBJETS DE SURVIE --
 select overall_survival, 
		CASE 
        when vital_status = 'DECEASED' THEN 1
        ELSE 0
        END as event
        from clinical_HNSC_cl
        
        where overall_survival <> CASE 
        when vital_status = 'DECEASED' THEN 1
        ELSE 0
        END;

SELECT
    overall_survival_time,
    COALESCE(days_to_death, days_to_last_followup) AS time_manual
FROM clinical_HNSC_cl;


INSERT INTO survival ( 
	patient_id,
	time,
	event)

SELECT 
	bcr_patient_barcode,
	overall_survival_time,
	CASE 
		when vital_status = 'DECEASED' THEN 1
		ELSE 0
	END as event
from clinical_HNSC_cl ;
        
 
ALTER TABLE survival 
ADD PRIMARY KEY (patient_id);

describe survival;

----------------------------------------- Nettoyage et préparation des données---------------------------------------------------
-- Verification de la correspondance  des lignes des tables -- 
-- Patients --
SELECT COUNT(*) 
FROM patients;

-- Tumor --
SELECT COUNT(*) 
FROM tumor; 

-- Survival --
SELECT COUNT(*)
FROM survival;

-- Gestion des valeurs manquantes  (table patients) --
-- Diagnostic du nombre de valeurs nulles par colonnes --

SELECT 	SUM(CASE WHEN age_at_diagnosis is null then 1 ELSE 0 END ) as nb_null_age,
		SUM(CASE WHEN gender is null then 1 ELSE 0 END ) as nb_null_genre,
		SUM(CASE WHEN hpv_status is null then 1 ELSE 0 END ) as nb_null_HPV,
		SUM(CASE when alcohol_use is null then 1 ELSE 0 END) as nb_null_alcohol,
		SUM(CASE when smoking_history  is null then 1 ELSE 0 END) as nb_null_smoke,
        SUM(CASE WHEN age_at_diagnosis='' then 1 ELSE 0 END ) as nb_vide_age,
        SUM(CASE WHEN gender='' then 1 ELSE 0 END ) as nb_vide_genre,
        SUM(CASE WHEN hpv_status='' then 1 ELSE 0 END ) as nb_vide_hpv,
        SUM(CASE WHEN alcohol_use='' then 1 ELSE 0 END ) as nb_vide_alcohol,
        SUM(CASE WHEN smoking_history='' then 1 ELSE 0 END ) as nb_vide_smoke
FROM patients;
-- > 410  données manquantes concernant le HPV (70%), 12 val manquante concernant l'historique de tabac et 11 pour l'alcool (on essaie de concerver le maximum d'obs 511 -- 

-- Concordance des variable hpv_statut et hpv_by_ish --
SELECT
    hpv_status_by_p16,
    hpv_status_by_ish_testing,
    COUNT(*) AS n
FROM clinical_HNSC_cl
GROUP BY
    hpv_status_by_p16,
    hpv_status_by_ish_testing;

-- On recupère les informations des test HPV --
 
ALTER TABLE patients 
add column hpv_test varchar(20);
UPDATE patients p
JOIN clinical_HNSC_cl ch
on p.patient_id=ch.bcr_patient_barcode
SET hpv_test = hpv_status_by_ish_testing
WHERE hpv_status_by_p16 = '' ;

-- Information  récupérée par la création de la nouvelles variable -- 
SELECT 
	SUM( CASE WHEN hpv_test = '' then 1 ELSE 0 END ) as hpv_test_vide,
	SUM( CASE WHEN hpv_test is null then 1 ELSE 0 END ) as hpv_test_null
FROM patients ;
-- > On récupère seulement 17 obs , on a 400 données manquantes sur 521 obs --

-- smocke et test_hpv, declarées nulles --
SET SQL_SAFE_UPDATES = 0;
update patients 
SET alcohol_use=NULLIF(alcohol_use,'');

UPDATE patients 
SET hpv_test=NULLIF(hpv_test,'');
SET SQL_SAFE_UPDATES = 1;
                   
SELECT smoking_history, count(*)
FROM patients 
group by smoking_history;

-- Création d'une variable statut tabagisme -- 
ALTER TABLE patients
add column tabac_status varchar(20);
SET SQL_safe_UPDATES = 0;
UPDATE patients
SET tabac_status= CASE
				WHEN smoking_history = 1 THEN 'never'
                WHEN smoking_history = 2 THEN 'current'
                WHEN smoking_history = 3 THEN 'former >15y'
                WHEN smoking_history = 4 THEN 'former<=15y'
                WHEN smoking_history = 5 THEN 'other'
                ELSE null
                END;
-- table tumor --

-- gestion de valeurs nulles --

-- Diagnostic --
SELECT SUM( case when pathologic_stage is null then 1 else 0 END ) as patho_stage_null,
		SUM(case when pathologic_stage = '' then 1 else 0 END) as patho_stage_vide,
        SUM(case when clinical_stage is null then 1 else 0 END) as clinical_stage_null,
		SUM(case when clinical_stage = '' then 1 else 0 END) as clinical_stage_vide,
        SUM(case when perineural_invasion = '' then 1 else 0 END) as perineural_invasion_vide,
		SUM(case when perineural_invasion is null then 1 else 0 END) as perineural_invasion_null,
		SUM(case when lymphvascular_invasion  = '' then 1 else 0 END) as lymphvascular_invasion_vide,
		SUM(case when lymphvascular_invasion is null then 1 else 0 END) as lymphvascular_invasion_null
FROM tumor;

-- déclarer les valeurs vides en nulles --
SET SQL_safe_UPDATES = 0;
UPDATE tumor
SET pathologic_stage=NULLIF(pathologic_stage,''),
	clinical_stage=NULLIF(clinical_stage,''),
    lymphvascular_invasion=NULLIF(lymphvascular_invasion,''),
    perineural_invasion=NULLIF(perineural_invasion,'');
    
SET SQL_safe_UPDATES = 1;

select lymphvascular_invasion,perineural_invasion,count(*) 
from tumor 
where lymphvascular_invasion is null and perineural_invasion is null
group by lymphvascular_invasion,perineural_invasion;


-- VAR clinical stage categorielle --

SET SQL_safe_UPDATES = 0;
UPDATE tumor 
SET clinical_stage=REPLACE(clinical_stage,'Stage', '');
SET SQL_safe_UPDATES = 1;


-- table survival --
SELECT sum(case when event is null then 1 else 0 end) as nb_null_event,
		sum(case when time is null then 1 else 0 end) as nb_time_null
FROM survival;        

-- Appariement des données --
CREATE VIEW dataset_surv_vw as (
SELECT p.patient_id, 
		p.age_at_diagnosis,
        p.gender,
        p.hpv_status,
        p.alcohol_use,
        p.smoking_history,
        p.tabac_status,
        
        t.clinical_stage,
        t.pathologic_stage,
        t.lymphvascular_invasion,
        t.perineural_invasion,
        
        s.event,
        s.time
FROM patients p 
left join tumor t
on p.patient_id=t.patient_id
left join survival s
on p.patient_id=s.patient_id );

SHOW FULL TABLES;
