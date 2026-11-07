// Test-only PDFBox raster oracle at an exact viewport width, including crop/rotation.
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.pdmodel.PDPage;
import org.apache.pdfbox.pdmodel.common.PDRectangle;
import org.apache.pdfbox.rendering.PDFRenderer;

class PdfboxRender {
    public static void main(String[] args) throws Exception {
        try (PDDocument doc = Loader.loadPDF(new File(args[0]))) {
            PDPage page = doc.getPage(0);
            PDRectangle box = page.getCropBox();
            boolean rotated = Math.floorMod(page.getRotation(), 180) != 0;
            double width = rotated ? box.getHeight() : box.getWidth();
            double height = rotated ? box.getWidth() : box.getHeight();
            int pixels = Integer.parseInt(args[2]);
            BufferedImage image = new BufferedImage(pixels, (int)Math.ceil(pixels * height / width), BufferedImage.TYPE_INT_RGB);
            Graphics2D graphics = image.createGraphics();
            graphics.setBackground(Color.WHITE);
            graphics.clearRect(0, 0, image.getWidth(), image.getHeight());
            try {
                float scale = (float)(pixels / width);
                new PDFRenderer(doc).renderPageToGraphics(0, graphics, scale, scale);
            } finally {
                graphics.dispose();
            }
            if (!ImageIO.write(image, "png", new File(args[1]))) throw new Exception("PNG writer unavailable");
        }
    }
}
