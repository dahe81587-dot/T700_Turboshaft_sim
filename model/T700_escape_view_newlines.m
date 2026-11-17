function count = T700_escape_view_newlines(fileName)
% Preserve embedded newlines as XML entities in an existing SDI view file.
validateattributes(fileName,{'char','string'},{'nonempty'});
assert(isfile(fileName),'T700:View:MissingFile','View file does not exist.');
work=tempname;mkdir(work);cleanup=onCleanup(@()rmdir(work,'s'));
unzip(fileName,work);
checked=fullfile(work,'views','sdi_checked_signals.xml');
assert(isfile(checked),'T700:View:MissingMetadata','Missing SDI view metadata.');
xml=fileread(checked);
[st,en,tok]=regexp(xml,'(?s)<(SignalName|LeafPath)>(.*?)</\1>','start','end','tokens');
count=0;
for k=numel(st):-1:1
    value=tok{k}{2};
    count=count+sum(value==newline)+sum(value==char(13));
    value=strrep(value,char(13),'&#13;');
    value=strrep(value,newline,'&#10;');
    xml=[xml(1:st(k)-1) '<' tok{k}{1} '>' value '</' tok{k}{1} '>' xml(en(k)+1:end)]; %#ok<AGROW>
end
fid=fopen(checked,'w','n','UTF-8');assert(fid>=0,'Cannot write temporary view metadata.');
c=onCleanup(@()fclose(fid));fwrite(fid,unicode2native(xml,'UTF-8'),'uint8');clear c;
files=dir(fullfile(work,'**','*'));files=files(~[files.isdir]);
relative=cell(size(files));
for k=1:numel(files)
    full=fullfile(files(k).folder,files(k).name);
    relative{k}=full(numel(work)+2:end);
end
archive=[tempname '.zip'];cleanupZip=onCleanup(@()removeTemporaryZip(archive));
zip(archive,relative,work);
[ok,msg]=movefile(archive,fileName,'f');assert(ok,'T700:View:Install','%s',msg);
end
function removeTemporaryZip(file)
if isfile(file),delete(file);end
end
