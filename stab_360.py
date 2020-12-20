# This file will take the video recording file as the input, stablises it and converts into a 360
# imagery. This imagery can be verified in a html page that gets generated in the root path.

from vidstab import VidStab
import math
import cv2
import sys
import os


directory = "reel_images"
parent_dir = str(os.getcwd().replace('\\','/'))
path = os.path.join(parent_dir, directory) 
 
try:
    os.mkdir(path) 
except:
    pass

stabilizer = VidStab()

# Traverse to this path and provide the video file name in the command line argument. That goes as
# sys.argv[1].
stabilizer.stabilize(input_path=sys.argv[1], 
                     output_path='rep_stable_video.avi', 
                     border_type='replicate')

videoFile = 'rep_stable_video.avi'

cap = cv2.VideoCapture(videoFile)
videoname = videoFile.split('.')[0]
frameRate = cap.get(5) #frame rate
x=1
while(cap.isOpened()):
    frameId = cap.get(1) #current frame number
    ret, frame = cap.read()
    if (ret != True):
        break
    if (frameId % math.floor(frameRate) == 0):
        if(x<10):
            filename = videoname+'_frame0' +  str(int(x)) + ".jpg"
        else:
            filename = videoname+'_frame' +  str(int(x)) + ".jpg"
        x+=1
        cv2.imwrite('reel_images/'+filename, frame)

cap.release()

try:
    for i in range(x+1,x+100):
        os.remove('reel_images/'+videoname+'_frame' +  str(int(i)) + ".jpg")
except:
    pass

from bs4 import BeautifulSoup


contents = '<!DOCTYPE html><html data-id="sequence-camera" data-type="example"><head><title>jQuery Reel Bare Camera Sequence Object Movie Example</title><meta charset="utf-8" content="text/html" http-equiv="Content-type"/><script src="http://code.jquery.com/jquery-1.9.1.min.js" type="text/javascript"></script><script src="http://code.vostrel.net/jquery.reel-bundle.js" type="text/javascript"></script><!-- Common examples style (gray background, thin fonts etc.) --><!-- <link href="../style.css" rel="stylesheet" type="text/css" /> --></head><body><center><img class="reel" data-images="reel_images/rep_stable_video_frame##.JPG|02..98" height="540" id="image" src="reel_images/rep_stable_video_frame02.JPG" width="960"/></center></body></html>'
soup = BeautifulSoup(contents, 'lxml')
soup.img['data-images'] = str(os.getcwd().replace('\\','/'))+'/reel_images/rep_stable_video_frame##.JPG|02..'+str(x-1)
with open("index.html", "w") as file:
    file.write(str(soup))
file.close()





