--
-- PostgreSQL database dump
--

-- Dumped from database version 16.4 (Ubuntu 16.4-1.pgdg24.04+1)
-- Dumped by pg_dump version 16.4 (Ubuntu 16.4-1.pgdg24.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

BEGIN;

--
-- Name: positions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.positions (
    position_id integer NOT NULL,
    vessel_code character varying(32) NOT NULL,
    cargo_kg integer NOT NULL,
    tariff_code character varying(16) NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    seal_tag character varying(24) NOT NULL
);

--
-- Data for Name: positions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.positions (position_id, vessel_code, cargo_kg, tariff_code, updated_at, seal_tag) FROM stdin;
1001	CS-PEGASUS	17130	TRF-0584	2024-07-24 16:48:00+00	KEEP-THETA
1002	CS-SIRIUS	68967	TRF-0650	2024-05-19 22:53:00+00	KEEP-IOTA
1003	MV-MERLIN	39315	TRF-7614	2024-05-07 19:09:00+00	KEEP-KAPPA
1004	MV-MERLIN	65454	TRF-5794	2024-08-28 21:30:00+00	ROUTINE
1005	MV-KESTREL	37963	TRF-5998	2024-08-09 15:58:00+00	ROUTINE
1006	CS-SIRIUS	41126	TRF-6033	2024-09-22 05:42:00+00	ROUTINE
1007	MSC-VEGA	49606	TRF-5790	2024-06-09 02:05:00+00	ROUTINE
1008	CS-SIRIUS	79046	TRF-2323	2024-05-18 01:48:00+00	ROUTINE
1009	MSC-VEGA	3886	TRF-6944	2024-06-28 14:56:00+00	ROUTINE
1010	MSC-VEGA	65597	TRF-3459	2024-11-07 08:44:00+00	ROUTINE
1011	CS-RIGEL	78991	TRF-6373	2024-09-30 14:09:00+00	ROUTINE
1012	MV-OSPREY	49250	TRF-5036	2024-05-14 13:14:00+00	ROUTINE
1013	CS-TRITON	81188	TRF-0536	2024-06-02 18:07:00+00	ROUTINE
1014	MV-CONDOR	81310	TRF-4159	2024-07-07 11:22:00+00	ROUTINE
1015	CS-SIRIUS	63830	TRF-4505	2024-08-28 01:39:00+00	ROUTINE
1016	MSC-ATLAS	90061	TRF-6979	2024-05-12 17:12:00+00	ROUTINE
1017	MV-OSPREY	6596	TRF-9937	2024-09-23 21:18:00+00	ROUTINE
1018	MSC-ORION	86625	TRF-4097	2024-11-06 21:11:00+00	ROUTINE
1019	CS-PEGASUS	45552	TRF-6378	2024-10-01 09:48:00+00	ROUTINE
1020	MSC-VEGA	40930	TRF-2437	2024-11-16 02:56:00+00	ROUTINE
\.

--
-- Name: positions positions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.positions
    ADD CONSTRAINT positions_pkey PRIMARY KEY (position_id);

--
-- PostgreSQL database dump complete
--

COMMIT;
