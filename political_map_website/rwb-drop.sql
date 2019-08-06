--
-- Part of the Red, White, and Blue example application
-- from EECS 339 at Northwestern University
--
--
-- This code drops the student *part* of the Red, White, 
-- and Blue data schema.  

delete from rwb_permissions;
delete from rwb_users;
delete from rwb_actions;
delete from rwb_opinions;
delete from rwb_cs_ind_to_geo;

commit;

drop table rwb_cs_ind_to_geo;
drop table rwb_opinions;
drop table rwb_permissions;
drop table rwb_actions;
drop table rwb_users;




quit;