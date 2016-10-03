xquery version "3.1";
module namespace serialize = 'http://bioimages.vanderbilt.edu/xqm/serialize';
import module namespace propvalue = 'http://bioimages.vanderbilt.edu/xqm/propvalue' at 'https://raw.githubusercontent.com/HeardLibrary/semantic-web/master/2016-fall/tang-song/propvalue.xqm'; (: can substitute local directory if you need to mess with it :)
(:--------------------------------------------------------------------------------------------------:)

declare function serialize:main($id,$serialization,$repoPath,$pcRepoLocation,$singleOrDump)
{
(: will use a variation on this if outputting to a file
let $localFilesFolderPC := "c:\github\semantic-web\2016-fall\tang-song\" :)

let $localFilesFolderUnix := 
  if (fn:substring(file:current-dir(),1,2) = "C:") 
  then 
    (: the computer is a PC with a C: drive, subsitute your path here :)
    "file:///"||$pcRepoLocation||$repoPath
  else
    (: its a Mac with the query running from a repo located at the default under the user directory :)
    file:current-dir() || "/Repositories/"||$repoPath

let $metadataDoc := file:read-text($localFilesFolderUnix || 'metadata.csv')
(: at some point if files are stable enough, they could be loaded from the GitHub repo like this:
let $metadataDoc := http:send-request(<http:request method='get' href='https://raw.githubusercontent.com/HeardLibrary/semantic-web/master/2016-fall/code/metadata.csv'/>)[2] :)
let $xmlMetadata := csv:parse($metadataDoc, map { 'header' : true(),'separator' : "," })
let $constantsDoc := file:read-text(concat($localFilesFolderUnix, 'constants.csv'))
let $xmlConstants := csv:parse($constantsDoc, map { 'header' : true(),'separator' : "," })
let $columnIndexDoc := file:read-text(concat($localFilesFolderUnix, 'metadata-column-mappings.csv'))
let $xmlColumnIndex := csv:parse($columnIndexDoc, map { 'header' : true(),'separator' : "," })
let $namespaceDoc := file:read-text(concat($localFilesFolderUnix,'namespace.csv'))
let $xmlNamespace := csv:parse($namespaceDoc, map { 'header' : true(),'separator' : "," })
let $classesDoc := file:read-text(concat($localFilesFolderUnix,'metadata-classes.csv'))
let $xmlClasses := csv:parse($classesDoc, map { 'header' : true(),'separator' : "," })
let $linkedClassesDoc := file:read-text(concat($localFilesFolderUnix,'linked-classes.csv'))
let $xmlLinkedClasses := csv:parse($linkedClassesDoc, map { 'header' : true(),'separator' : "," })

let $namespaces := $xmlNamespace/csv/record
let $columnInfo := $xmlColumnIndex/csv/record
let $classes := $xmlClasses/csv/record
let $linkedClasses := $xmlLinkedClasses/csv/record
let $constants := $xmlConstants/csv/record
let $domainRoot := $constants//domainRoot/text()

let $linkedMetadata :=
      for $class in $linkedClasses
      let $classMappingDoc := file:read-text(concat($localFilesFolderUnix,$class/filename/text(),"-column-mappings.csv"))
      let $xmlClassMapping := csv:parse($classMappingDoc, map { 'header' : true(),'separator' : "," })
      let $classClassesDoc := file:read-text(concat($localFilesFolderUnix,$class/filename/text(),"-classes.csv"))
      let $xmlClassClasses := csv:parse($classClassesDoc, map { 'header' : true(),'separator' : "," })
      let $classMetadataDoc := file:read-text(concat($localFilesFolderUnix,$class/filename/text(),".csv"))
      let $xmlClassMetadata := csv:parse($classMetadataDoc, map { 'header' : true(),'separator' : "," })
      return
        ( 
        <file>{
          $class/link_column,
          $class/link_property,
          $class/suffix1,
          $class/link_characters,
          $class/suffix2,
          $class/class,
          <classes>{
            $xmlClassClasses/csv/record
          }</classes>,
          <mapping>{
            $xmlClassMapping/csv/record
          }</mapping>,
          <metadata>{
            $xmlClassMetadata/csv/record
          }</metadata>
       }</file>
       )
  
(: The main function returns a single string formed by concatenating all of the assembled pieces of the document :)
return (
  concat( 
    (: the namespace abbreviations only needs to be generated once for the entire document :)
    serialize:list-namespaces($namespaces,$serialization),
    string-join( 
      if ($singleOrDump = "dump")
      then
        (: this case outputs every record in the database :)
        for $record in $xmlMetadata/csv/record
        let $baseIRI := $domainRoot||$record/iri_local_name/text()
        let $modified := $record/modified/text()
        return serialize:generate-a-record($record,$linkedMetadata,$baseIRI,$domainRoot,$modified,$classes,$columnInfo,$serialization,$namespaces,$constants)
      else
        (: for a single record, each record in the database must be checked for a match to the requested URI :)
        for $record in $xmlMetadata/csv/record
        where $record/iri_local_name/text()=$id
        let $baseIRI := $domainRoot||$record/iri_local_name/text()
        let $modified := $record/modified/text()
        return serialize:generate-a-record($record,$linkedMetadata,$baseIRI,$domainRoot,$modified,$classes,$columnInfo,$serialization,$namespaces,$constants)      
      ),
    serialize:close-container($serialization) 
    ) 
  )
};

declare function serialize:generate-a-record($record,$linkedMetadata,$baseIRI,$domainRoot,$modified,$classes,$columnInfo,$serialization,$namespaces,$constants)
{
        
          (: Generate unabbreviated URIs and blank node identifiers. This must be done for every record separately since the UUIDs generated for the blank node identifiers must be the same within a record, but differ among records. :)
          
          let $IRIs := serialize:construct-iri($baseIRI,$classes) 
          (: generate a description for each class of resource included in the record :)
          for $modifiedClass in $IRIs
          return serialize:describe-resource($IRIs,$columnInfo,$record,$modifiedClass,$serialization,$namespaces,"") 
          ,
          
          (: now step through each class that's linked to the root class by many-to-one relationships and generate the resource description for each linked resource in that class :)
          for $linkedClass in $linkedMetadata
          return (
            (: determine the constants for the linked class :)
            let $linkColumn := $linkedClass/link_column/text()
            let $linkProperty := $linkedClass/link_property/text()
            let $suffix1 := $linkedClass/suffix1/text()
            let $linkCharacters := $linkedClass/link_characters/text()
            let $suffix2 := $linkedClass/suffix2/text()
            let $linkedClassType := $linkedClass/class/text()
            
            for $linkedClassRecord in $linkedClass/metadata/record
            where $baseIRI=$domainRoot||$linkedClassRecord/*[local-name()=$linkColumn]/text()
            (: generate an IRI for the instance of the linked class based on the convention for that class :)
            let $linkedClassIRI := $baseIRI||"#"||$linkedClassRecord/*[local-name()=$suffix1]/text()||$linkCharacters||$linkedClassRecord/*[local-name()=$suffix2]/text()
            let $linkedIRIs := serialize:construct-iri($linkedClassIRI,$linkedClass/classes/record)
            let $extraTriple := propvalue:iri($linkProperty,$baseIRI,$serialization,$namespaces)
            for $linkedModifiedClass in $linkedIRIs
            return
               serialize:describe-resource($linkedIRIs,$linkedClass/mapping/record,$linkedClassRecord,$linkedModifiedClass,$serialization,$namespaces,$extraTriple) 
          )
          ,
          
          (: The document description is done once for each record. :)
          serialize:describe-document($baseIRI,$modified,$serialization,$namespaces,$constants)
        
};

(:--------------------------------------------------------------------------------------------------:)

declare function serialize:describe-document($baseIRI,$modified,$serialization,$namespaces,$constants)
{
  let $type := $constants//documentClass/text()
  let $suffix := propvalue:extension($serialization)
  let $iri := concat($baseIRI,$suffix)
  return concat(
    propvalue:subject($iri,$serialization),
    propvalue:plain-literal("dc:format",propvalue:media-type($serialization),$serialization),
    propvalue:plain-literal("dc:creator",$constants//creator/text(),$serialization),
    propvalue:iri("dcterms:references",$baseIRI,$serialization,$namespaces),
    if ($modified)
    then propvalue:datatyped-literal("dcterms:modified",$modified,"http://www.w3.org/2001/XMLSchema#dateTime",$serialization,$namespaces)
    else "",
    propvalue:type($type,$serialization,$namespaces)
  )  
};

(:--------------------------------------------------------------------------------------------------:)

declare function serialize:remove-last-comma($temp)
{
  concat(fn:substring($temp,1,fn:string-length($temp)-2),"&#10;")
};

(:--------------------------------------------------------------------------------------------------:)

(: This generates the list of namespace abbreviations used :)
declare function serialize:list-namespaces($namespaces,$serialization)
{  
(: Because this is the beginning of the file, it also opens the root container for the serialization (if any) :)
switch ($serialization)
    case "turtle" return concat(
                          string-join(serialize:curie-value-pairs($namespaces,$serialization)),
                          "&#10;"
                        )
    case "xml" return concat(
                          "<rdf:RDF&#10;",
                          string-join(serialize:curie-value-pairs($namespaces,$serialization)),
                          ">&#10;"
                        )
    case "json" return concat(
                          "{&#10;",
                          '"@context": {&#10;',
                          serialize:remove-last-comma(string-join(serialize:curie-value-pairs($namespaces,$serialization))),
                          '},&#10;',
                          '"@graph": [&#10;'
                        )
    default return ""
};

(:--------------------------------------------------------------------------------------------------:)

(: generate sequence of CURIE,value pairs :)
declare function serialize:curie-value-pairs($namespaces,$serialization)
{
  for $namespace in $namespaces
  return switch ($serialization)
        case "turtle" return concat("@prefix ",$namespace/curie/text(),": <",$namespace/value/text(),">.&#10;")
        case "xml" return concat('xmlns:',$namespace/curie/text(),'="',$namespace/value/text(),'"&#10;')
        case "json" return concat('"',$namespace/curie/text(),'": "',$namespace/value/text(),'",&#10;')
        default return ""
};

(:--------------------------------------------------------------------------------------------------:)

(: This function describes a single instance of the type of resource being described by the table :)
declare function serialize:describe-resource($IRIs,$columnInfo,$record,$class,$serialization,$namespaces,$extraTriple)
{  
(: Note: the propvalue:subject function sets up any string necessary to open the container, and the propvalue:type function closes the container :)
  let $type := $class/class/text()
  let $suffix := $class/id/text()
  let $iri := $class/fullId/text()
  return concat(
    propvalue:subject($iri,$serialization),
    string-join(serialize:property-value-pairs($IRIs,$columnInfo,$record,$type,$serialization,$namespaces)),

(: make the backlink only for the instance of the primary class in a table :)
    if (not($suffix))
    then $extraTriple
    else ""
    ,
    propvalue:type($type,$serialization,$namespaces)
  )
  ,
  (: each described resource must be separated by a comma in JSON. The last described resource is the document, which isn't followed by a trailing comma :)
  if ($serialization="json")
  then ",&#10;"
  else ""
};

(:--------------------------------------------------------------------------------------------------:)

(: generate sequence of non-type property/value pair strings :)
declare function serialize:property-value-pairs($IRIs,$columnInfo,$record,$type,$serialization,$namespaces)
{
  (: generates property/value pairs that have fixed values :)
  for $columnType in $columnInfo
  where "$constant" = $columnType/header/text() and $columnType/class/text() = $type
  return switch ($columnType/type/text())
     case "plain" return propvalue:plain-literal($columnType/predicate/text(),$columnType/value/text(),$serialization)
     case "datatype" return propvalue:datatyped-literal($columnType/predicate/text(),$columnType/value/text(),$columnType/attribute/text(),$serialization,$namespaces)
     case "language" return propvalue:language-tagged-literal($columnType/predicate/text(),$columnType/value/text(),$columnType/attribute/text(),$serialization)
     case "iri" return propvalue:iri($columnType/predicate/text(),$columnType/value/text(),$serialization,$namespaces)
     default return ""
,

  (: generates property/value pairs whose values are given in the metadata table :)
  for $column in $record/child::*, $columnType in $columnInfo
  (: The loop only includes columns containing properties associated with the class of the described resource; that column in the record must not be empty :)
  where fn:local-name($column) = $columnType/header/text() and $columnType/class/text() = $type and $column//text() != ""
  return switch ($columnType/type/text())
     case "plain" return propvalue:plain-literal($columnType/predicate/text(),$column//text(),$serialization)
     case "datatype" return propvalue:datatyped-literal($columnType/predicate/text(),$column//text(),$columnType/attribute/text(),$serialization,$namespaces)
     case "language" return propvalue:language-tagged-literal($columnType/predicate/text(),$column//text(),$columnType/attribute/text(),$serialization)
     case "iri" return propvalue:iri($columnType/predicate/text(),$column//text(),$serialization,$namespaces)
     default return ""
,

  (: generates links to associated resources described in the same document :)
  for $columnType in $columnInfo
  where "$link" = $columnType/header/text() and $columnType/class/text() = $type
  let $suffix := $columnType/value/text()
  return 
      for $iri in $IRIs
      where $iri/id/text()=$suffix
      let $object := $iri/fullId/text()
      return propvalue:iri($columnType/predicate/text(),$object,$serialization,$namespaces)
};

(:--------------------------------------------------------------------------------------------------:)

(: this function closes the root container for the serialization (if any) :)
declare function serialize:close-container($serialization)
{  
switch ($serialization)
    case "turtle" return ""
    case "xml" return "</rdf:RDF>&#10;"
    case "json" return ']&#10;}'
    default return ""
};

(:--------------------------------------------------------------------------------------------------:)

declare function serialize:construct-iri($baseIRI,$classes)
{
  (: This function basically creates a parallel set of class records that contain the full URIs in addition to the abbreviated ones that are found in classes.csv . In addition, UUID blank node identifiers are generated for nodes that are anonymous.  UUIDs are used instead of sequential numbers since the main function may be hacked to serializa ALL records rather than just one and in that case using UUIDs would ensure that there is no duplication of blank node identifiers among records. :)
  for $class in $classes
  let $suffix := $class/id/text()
  return
     <record>{
     if (fn:substring($suffix,1,2)="_:")
     then (<fullId>{concat("_:",random:uuid() ) }</fullId>, $class/id, $class/class )
     else (<fullId>{concat($baseIRI,$suffix) }</fullId>, $class/id, $class/class )
   }</record>
};

(:--------------------------------------------------------------------------------------------------:)

declare function serialize:html($id,$serialization)
{
 let $value := concat("Placeholder page for local ID=",$id,".")
return 
<html>
  <body>
  {$value}
  </body>
</html>
};
