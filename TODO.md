* [X] color

&r darkred   &R brightred  &g darkgreen  &G brightgreen
&b darkblue  &B lightblue  &C lightcyan  &W white
&Y yellow    &O orange     &p darkpurple &P lightpurple
&c darkcyan  &w lightgrey  &z darkgrey   && an ampersand (&)
&. random color

* [ ] real systems implementation
* [X] removal of entities from World
* [ ] World tests, including stress test with 10000's of entities
* [ ] command expansion
    * register commands with priorities; exact match wins; highest priority
      partial match after
* [X] generic error method
    * [X] save error to system-wide error log w/ binding
    * [X] write error message to error log
    * [ ] send error to user
* [ ] not_implemented method; output message to entity
* [ ] Entity composition
    * [X] implementation
    * [ ] tests
* [ ] WBR area file loader
* [ ] Entity save method
* [ ] Unload Entities from a given source filename
    * [ ] reload a specific source filename
* [ ] Implement entity tags
    * ~~Alternate: regex support for `entity_by_virtual`~~ not everything will
      have a virtual
